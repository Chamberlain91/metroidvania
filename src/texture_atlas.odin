package metroidvania_game

import "core:encoding/xml"
import "core:log"
import "core:path/slashpath"
import "core:strconv"
import "core:strings"
import "deps:oak/core"
import "deps:oak/gpu"
import stb_image "vendor:stb/image"

Texture_Atlas :: struct {
    images: map[string]^gpu.Image,
    keys:   strings.Intern,
}

atlas_load_kenney_spritesheet :: proc(atlas: ^Texture_Atlas, path: string) {

    bytes, bytes_ok := core.get_asset(path)
    if !bytes_ok {
        atlas_panic(path, "Could not read embedded file")
    }

    // Parse the XML.
    doc, doc_err := xml.parse_bytes(bytes)
    if doc_err != nil {
        atlas_panic(path, doc_err)
    }
    defer xml.destroy(doc)

    // Find the image path.
    image_path, image_path_ok := xml.find_attribute_val_by_key(doc, 0, "imagePath")
    if !image_path_ok {
        atlas_panic(path, "Invalid XML structure.")
    }

    // Load the image relative to the XML.
    dir, _ := slashpath.split(path)
    image_path = slashpath.join({dir, image_path}, context.temp_allocator)
    pixels, pixels_ok := load_image(image_path)
    if !pixels_ok {
        atlas_panic(path, "Could not read embedded image file.")
    }
    defer free_image(pixels)

    root_element := doc.elements[0]
    for value in root_element.value {
        child_id, child_id_ok := value.(xml.Element_ID)
        if !child_id_ok {
            atlas_panic(path, "Invalid XML structure.")
        }

        assert(doc.elements[child_id].ident == "SubTexture")

        // Read the SubTexture node
        n, x, y, w, h := read_subtexture(path, doc, child_id)

        // Store the image sliced out of the spritesheet.
        atlas_insert(atlas, n, extract_image(pixels, x, y, w, h))
    }

    return

    read_subtexture :: proc(
        path: string,
        doc: ^xml.Document,
        id: xml.Element_ID,
    ) -> (
        name: string,
        x: int,
        y: int,
        w: int,
        h: int,
    ) {

        n_str, n_str_ok := xml.find_attribute_val_by_key(doc, id, "name")
        if !n_str_ok {
            atlas_panic(path, "Invalid XML structure, missing 'name' attribute.")
        }
        x_str, x_str_ok := xml.find_attribute_val_by_key(doc, id, "x")
        if !x_str_ok {
            atlas_panic(path, "Invalid XML structure, missing 'x' attribute.")
        }
        y_str, y_str_ok := xml.find_attribute_val_by_key(doc, id, "y")
        if !y_str_ok {
            atlas_panic(path, "Invalid XML structure, missing 'y' attribute.")
        }
        w_str, w_str_ok := xml.find_attribute_val_by_key(doc, id, "width")
        if !w_str_ok {
            atlas_panic(path, "Invalid XML structure, missing 'width' attribute.")
        }
        h_str, h_str_ok := xml.find_attribute_val_by_key(doc, id, "height")
        if !h_str_ok {
            atlas_panic(path, "Invalid XML structure, missing 'height' attribute.")
        }

        x = strconv.parse_int(x_str) or_else atlas_panic(path, "Failed to parse integer.")
        y = strconv.parse_int(y_str) or_else atlas_panic(path, "Failed to parse integer.")
        w = strconv.parse_int(w_str) or_else atlas_panic(path, "Failed to parse integer.")
        h = strconv.parse_int(h_str) or_else atlas_panic(path, "Failed to parse integer.")
        name = n_str

        return
    }

    extract_image :: proc(pixels: Pixel_Image, x, y, w, h: int) -> ^gpu.Image {

        tile: [dynamic]byte
        defer delete(tile)

        reserve(&tile, w * h * 4)
        for i in y ..< (y + h) {
            row_start := (i * pixels.width * 4) + (x * 4)
            append_elems(&tile, ..pixels.pixels[row_start:row_start + w * 4])
        }

        image := gpu.create_image_2D(.RGBA8_UNORM, {w, h})
        gpu.update_image_whole(image, tile[:])
        return image
    }

    atlas_panic :: proc(path: string, value: any) -> ! {
        log.panicf("Could not load '{}' as Kenney spritesheet: {}", path, value)
    }
}

atlas_destroy :: proc(atlas: ^Texture_Atlas) {
    // Delete each atlas image.
    for _, image in atlas.images {
        gpu.delete_image(image)
    }
    // Delete each the keys.
    strings.intern_destroy(&atlas.keys)
    // Delete the whole map.
    delete(atlas.images)
}

atlas_insert :: proc(atlas: ^Texture_Atlas, name: string, image: ^gpu.Image) {

    key, key_err := strings.intern_get(&atlas.keys, name)
    if key_err != nil {
        log.panicf("Could not intern atlas key.")
    }

    atlas.images[key] = image
}

atlas_get_image :: proc(atlas: Texture_Atlas, name: string) -> (image: ^gpu.Image, ok: bool) #optional_ok {
    return atlas.images[name]
}

@(private = "file")
Pixel_Image :: struct {
    pixels:        []byte,
    width, height: int,
}

@(private = "file")
load_image :: proc(path: string) -> (image: Pixel_Image, ok: bool) {

    data := core.get_asset(path) or_return

    w, h: i32
    pixels := stb_image.load_from_memory(raw_data(data), cast(i32)len(data), &w, &h, nil, 4)
    if pixels == nil {
        log.errorf("Something went wrong loading image '{}'.", path)
        return
    }

    ok = true
    image = Pixel_Image {
        pixels = pixels[:w * h * 4],
        width  = cast(int)w,
        height = cast(int)h,
    }

    return
}

@(private = "file")
free_image :: proc(image: Pixel_Image) {
    if ptr := raw_data(image.pixels); ptr != nil {
        stb_image.image_free(ptr)
    }
}
