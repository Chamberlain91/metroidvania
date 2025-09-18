package metroidvania_game

import "core:fmt"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "core:path/slashpath"
import "core:strings"
import "core:time"
import "deps:oak/core"
import "deps:oak/ds"
import "deps:oak/gpu"
import "deps:oak/sound"

BUILD_SHADERS :: #config(BUILD_SHADERS, false)

main :: proc() {

    context = core.scoped_standard_context()

    when BUILD_SHADERS {
        gpu.generate_shader_source("src/shaders/oak.hlsli", Sprite_Push_Constants, Line_Push_Constants)
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
        sprites: ^gpu.Graphics_Shader,
        lines:   ^gpu.Graphics_Shader,
    },
    sprites:         struct {
        tile: ^gpu.Image,
    },
    sprite_renderer: Sprite_Renderer,
    line_renderer:   Line_Renderer,
    atlas:           Texture_Atlas,
    camera_matrix:   gpu.mat4x4,
    player_rect:     ds.BVH_Rect,
}

app_initialize :: proc(state: ^AppState) {

    // Maintain the primary monitor target FPS.
    core.set_target_frame_duration(time.Second / cast(time.Duration)core.get_monitor_refresh_rate())

    // Register embedded in-memory assets.
    // TODO: Rename to register_embedded_files() and get_embedded_file() or something like that.
    core.embed_assets(#load_directory("assets/shaders"), prefix = "shaders")

    // Load the Kenney spritesheets.
    core.embed_assets(#load_directory("assets/sprites"), prefix = "sprites")
    for file in #load_directory("assets/sprites") do if strings.ends_with(file.name, ".xml") {
        atlas_load_kenney_spritesheet(&state.atlas, slashpath.join({"sprites", file.name}, context.temp_allocator))
    }

    // TODO: Unify with core file/asset system somehow?
    for file in #load_directory("assets/sounds") {
        path := slashpath.join({"sounds", file.name}, context.temp_allocator)
        sound.register_audio_data(path, file.data)
    }

    defer gpu.memory_barrier()

    // LOAD SHADERS
    {
        sprites_vert := cast(gpu.Shader_Binary)core.get_asset("shaders/world.vert.spv")
        sprites_frag := cast(gpu.Shader_Binary)core.get_asset("shaders/world.frag.spv")
        state.shaders.sprites = gpu.create_graphics_shader(sprites_vert, sprites_frag)

        lines_vert := cast(gpu.Shader_Binary)core.get_asset("shaders/lines.vert.spv")
        lines_frag := cast(gpu.Shader_Binary)core.get_asset("shaders/lines.frag.spv")
        state.shaders.lines = gpu.create_graphics_shader(lines_vert, lines_frag)
    }

    // REGISTER PROJECT ENUMS
    project_register_enum(Toggle_Color)

    // REGISTER PROJECT ENTITIES
    project_register_entity(Player)
    project_register_entity(Star)
    project_register_entity(Toggle_Block)
    project_register_entity(Toggle_Button)

    // INIT PROJECT (LOAD AND VALIDATE)
    // TODO: Return some project/world datatype?
    project_init()

    state.sprites.tile = atlas_get_image(state.atlas, "character_green_idle")
}

app_shutdown :: proc(state: ^AppState) {

    gpu.delete_graphics_shader(state.shaders.sprites)
    gpu.delete_graphics_shader(state.shaders.lines)

    atlas_destroy(&state.atlas)
    delete(state.sprite_renderer.instances)
    destroy_project()
}

app_update :: proc(state: ^AppState) {

    fb_width, fb_height := expand_values(core.get_framebuffer_size())
    aspect := cast(f32)fb_width / cast(f32)fb_height

    cam_height: f32 = 1024
    cam_width: f32 = 1024 * aspect

    cam_x := -(cam_width - cam_height) / 2

    state.camera_matrix = gpu.ortho_matrix(cam_width, cam_height) * glsl.mat4Translate({-cam_x, 0.0, 0.0})

    // Maps mouse screen to world.
    ndc_to_world := linalg.inverse(state.camera_matrix)
    mouse_screen := core.mouse_position()
    mouse_ndc := ([2]f32{mouse_screen.x / cast(f32)fb_width, mouse_screen.y / cast(f32)fb_height} * 2.0) - 1.0
    mouse_world := ndc_to_world * [4]f32{mouse_ndc.x, -mouse_ndc.y, 0.0, 1.0}
    mx, my := cast(int)mouse_world.x, cast(int)mouse_world.y

    sprite_renderer_append(&state.sprite_renderer, {mx, my}, state.sprites.tile)

    state.player_rect = {
        cast(i32)mx,
        cast(i32)my,
        cast(i32)state.sprites.tile.size.x,
        cast(i32)state.sprites.tile.size.y,
    }
    line_renderer_append_rect(&state.line_renderer, linalg.array_cast(state.player_rect, int), .Yellow)

    level := &levels["level_0"]
    {
        for c in level.colliders {
            line_renderer_append_rect(&state.line_renderer, linalg.array_cast(c.rect, int), .Gray)
        }

        ds.bvh_traverse_predicate(&level.colliders_bvh, proc(rect: ds.BVH_Rect) -> bool {
            line_renderer_append_rect(&app.state.line_renderer, linalg.array_cast(rect, int), .Magenta)
            return ds.rect_overlaps(app.state.player_rect, rect)
        }, proc(collider: ^Collider) {
            line_renderer_append_rect(&app.state.line_renderer, linalg.array_cast(collider.rect, int), .Cyan)
        })
    }
}

app_render :: proc(state: ^AppState) {

    // Ephemeral buffer to draw sprites.
    sprite_buffer := sprite_renderer_to_buffer(&state.sprite_renderer)
    defer {
        sprite_renderer_clear(&state.sprite_renderer)
        gpu.delete_buffer(sprite_buffer)
    }

    // Ephemeral buffer to draw lines.
    line_buffer := line_renderer_to_buffer(&state.line_renderer)
    defer {
        line_renderer_clear(&state.line_renderer)
        gpu.delete_buffer(line_buffer)
    }

    attachments := gpu.Rendering_Info {
        color_attachments = {gpu.attachment(gpu.swapchain_image())},
    }
    gpu.begin_rendering(attachments)
    {
        // We are vertex pulling assembling quads (6x vertices).
        if count := len(state.sprite_renderer.instances); count > 0 {
            gpu.bind_graphics_shader(state.shaders.sprites)
            gpu.push_graphics_constant(
                Sprite_Push_Constants {
                    camera_matrix = state.camera_matrix,
                    sprite_buffer = gpu.buffer_reference(Sprite_Buffer, sprite_buffer),
                },
            )
            gpu.set_primitive_topology(.Triangle_List)
            gpu.draw(count * 6)
        }

        // We are assembling lines (2x vertices).
        if count := len(state.line_renderer.instances); count > 0 {
            gpu.bind_graphics_shader(state.shaders.lines)
            gpu.push_graphics_constant(
                Line_Push_Constants {
                    camera_matrix = state.camera_matrix,
                    line_buffer = gpu.buffer_reference(Line_Buffer, line_buffer),
                },
            )
            gpu.set_primitive_topology(.Line_List)
            gpu.draw(count * 2)
        }
    }
    gpu.end_rendering()

    // Present rendered content to the screen.
    gpu.submit_and_present()
}

gpu_swapchain_created :: proc(size: [2]int) {
    // Opportunity to (re)create any resources that depend on screen size.
}

Toggle_Color :: enum {
    Red,
    Yellow,
    Blue,
    Green,
}

Player :: struct {
    using _: Entity,
}

Star :: struct {
    using _: Entity,
}

Toggle_Block :: struct {
    using _: Entity,
    color:   Toggle_Color,
    state:   bool,
}

Toggle_Button :: struct {
    using _: Entity,
    color:   Toggle_Color,
}
