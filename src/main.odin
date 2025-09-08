package metroidvania_game

import "core:path/slashpath"
import "core:time"
import "oak:core"
import "oak:gpu"
import "oak:sound"
import stb_image "vendor:stb/image"

BUILD_SHADERS :: #config(BUILD_SHADERS, false)

main :: proc() {

    context = core.scoped_standard_context()

    when BUILD_SHADERS {
        gpu.generate_shader_source("src/shaders/oak.hlsli", Sprite_Push_Constants)
    }

    // Establish swapchain callback to (re)create GPU resources on window resize.
    gpu.set_swapchain_callback(gpu_swapchain_created)

    // Enables vsync by default.
    gpu.enable_vsync(true)

    // Run the game!
    core.run(&app, "Metroidvania Game")
}

app := core.App(AppState) {
    initialize = app_initialize,
    shutdown   = app_shutdown,
    update     = app_update,
    render     = app_render,
}

AppState :: struct {
    shaders:         struct {
        world: ^gpu.Graphics_Shader,
    },
    sprites:         struct {
        tile: ^gpu.Image,
    },
    sprite_renderer: Sprite_Renderer,
    camera_matrix:   gpu.mat4x4,
}

app_initialize :: proc(state: ^AppState) {

    // Maintain the primary monitor target FPS.
    core.set_target_frame_duration(time.Second / cast(time.Duration)core.get_monitor_refresh_rate())

    // Register embedded in-memory assets.
    // TODO: Rename to register_embedded_files() and get_embedded_file() or something like that.
    core.embed_assets(#load_directory("assets/shaders"), prefix = "shaders")
    core.embed_assets(#load_directory("assets/sprites/tiles"), prefix = "sprites/tiles")
    core.embed_assets(#load_directory("assets/sprites/enemies"), prefix = "sprites/enemies")
    core.embed_assets(#load_directory("assets/sprites/characters"), prefix = "sprites/characters")
    core.embed_assets(#load_directory("assets/sprites/backgrounds"), prefix = "sprites/backgrounds")

    // TODO: Unify with core file/asset system somehow.
    // core.embed_assets(#load_directory("assets/sounds"), prefix = "sounds")
    for file in #load_directory("assets/sounds") {
        path := slashpath.join({"sounds", file.name}, context.temp_allocator)
        sound.register_audio_data(path, file.data)
    }

    // LOAD SHADERS
    {
        world_vert := cast(gpu.Shader_Binary)core.get_asset("shaders/world.vert.spv")
        world_frag := cast(gpu.Shader_Binary)core.get_asset("shaders/world.frag.spv")
        state.shaders.world = gpu.create_graphics_shader(world_vert, world_frag)
    }

    // LOAD IMAGES
    {
        state.sprites.tile = load_image("sprites/tiles/block_blue.png")
    }

    load_image :: proc(path: string) -> ^gpu.Image {
        defer gpu.memory_barrier()

        image_bytes, image_bytes_ok := core.get_asset(path)
        if !image_bytes_ok {
            // TODO: Panic or log the error?
            return gpu.create_image_2D(.RGBA8_UNORM, {1, 1})
        }

        w, h: i32
        image_pixels := stb_image.load_from_memory(
            raw_data(image_bytes),
            cast(i32)len(image_bytes),
            &w,
            &h,
            nil,
            4,
        )
        defer stb_image.image_free(image_pixels)

        // Construct and upload decoded image data.
        image := gpu.create_image_2D(.RGBA8_UNORM, {cast(int)w, cast(int)h})
        gpu.update_image(image, image_pixels[:w * h * 4])
        return image
    }
}

app_shutdown :: proc(state: ^AppState) {
    gpu.delete_graphics_shader(state.shaders.world)
    gpu.delete_image(state.sprites.tile)
    delete(state.sprite_renderer.instances)
}

app_update :: proc(state: ^AppState) {
    width, height := expand_values(core.get_framebuffer_size())
    state.camera_matrix = gpu.ortho_matrix(cast(f32)width, cast(f32)height)

    sprite_renderer_append(&state.sprite_renderer, {10, 10}, state.sprites.tile)
}

app_render :: proc(state: ^AppState) {

    // Draw sprites.
    if len(state.sprite_renderer.instances) > 0 {

        defer sprite_renderer_clear(&state.sprite_renderer)

        // Ephemeral buffer to draw sprites.
        sprite_buffer := sprite_renderer_to_buffer(&state.sprite_renderer)
        defer gpu.delete_buffer(sprite_buffer)

        attachments := gpu.Rendering_Info {
            color_attachments = {gpu.attachment(gpu.swapchain_image())},
        }
        gpu.begin_rendering(attachments)
        defer gpu.end_rendering()

        gpu.bind_graphics_shader(state.shaders.world)

        constants := Sprite_Push_Constants {
            camera_matrix = state.camera_matrix,
            sprite_buffer = gpu.buffer_reference(Sprite_Buffer, sprite_buffer),
        }
        gpu.push_graphics_constant(constants)

        // We are vertex pulling assembling quads. So we issue 6x vertices to sprite instances.
        gpu.draw(len(state.sprite_renderer.instances) * 6)
    }

    // Present rendered content to the screen
    gpu.submit_and_present()
}

gpu_swapchain_created :: proc(size: [2]int) {
    // Opportunity to (re)create any resources that depend on screen size.
}
