package metroidvania_game

import "deps:oak/gpu"

Sprite_Renderer :: struct {
    instances: [dynamic]Sprite_Instance,
}

Sprite_Buffer :: struct {
    sprites: [0]Sprite_Instance,
}

Sprite_Instance :: struct {
    image: gpu.Image_View_Index,
    rect:  gpu.vec4,
}

Sprite_Push_Constants :: struct {
    camera_matrix: gpu.mat4x4,
    sprite_buffer: gpu.Buffer_Reference(Sprite_Buffer),
}

sprite_renderer_clear :: proc(renderer: ^Sprite_Renderer) {
    clear(&renderer.instances)
}

sprite_renderer_append :: proc(
    renderer: ^Sprite_Renderer,
    position: [2]int,
    image: ^gpu.Image,
    loc := #caller_location,
) {
    assert(image != nil, loc = loc)

    instance := Sprite_Instance {
        image = gpu.image_view_index(image),
        rect  = {     //
            cast(f32)position.x,
            cast(f32)position.y,
            cast(f32)image.size.x,
            cast(f32)image.size.y,
        },
    }
    append(&renderer.instances, instance)
}

@(require_results)
sprite_renderer_to_buffer :: proc(renderer: ^Sprite_Renderer) -> ^gpu.Buffer {
    if count := len(renderer.instances); count > 0 {
        buffer := gpu.create_buffer(size_of(Sprite_Renderer) * count)
        gpu.copy(buffer, 0, renderer.instances[:])
        gpu.memory_barrier() // TODO: Narrow to host memory
        return buffer
    } else {
        // No instances, no buffer
        return nil
    }
}
