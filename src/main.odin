package metroidvania_game

@(require) import "core:log"
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
    player:          Player,
    input:           struct {
        m_screen: [2]int,
        m_world:  [2]int,
        // TODO: Enum array of input states? ie. key[.Jump]
        k_left:   bool,
        k_right:  bool,
        k_jump:   bool,
    },
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

    change_level("level_0")
}

app_shutdown :: proc(state: ^AppState) {

    gpu.delete_graphics_shader(state.shaders.sprites)
    gpu.delete_graphics_shader(state.shaders.lines)

    atlas_destroy(&state.atlas)

    sprite_renderer_destroy(state.sprite_renderer)
    line_renderer_destroy(state.line_renderer)

    destroy_project()
}

app_update :: proc(state: ^AppState) {

    level := current_level()
    assert(level != nil)

    fb_width, fb_height := expand_values(core.get_framebuffer_size())
    aspect := cast(f32)fb_width / cast(f32)fb_height

    // TODO: Proper "view around the player" instead of zooming on the level
    max_level_dim := 1.1 * cast(f32)max(level.size.x, level.size.y)
    cam_h := max_level_dim
    cam_w := max_level_dim * aspect
    cam_x := cast(f32)(level.position.x + (level.size.x / 2)) - (cam_w / 2)
    cam_y := cast(f32)(level.position.y + (level.size.y / 2)) - (cam_h / 2)

    state.camera_matrix = gpu.ortho_matrix(cam_w, cam_h) * glsl.mat4Translate({-cam_x, -cam_y, 0.0})

    // Maps mouse screen position to world position.
    mouse_ndc := ((core.mouse_position() / [2]f32{cast(f32)fb_width, cast(f32)fb_height}) * 2.0) - 1.0
    mouse_world := linalg.inverse(state.camera_matrix) * [4]f32{mouse_ndc.x, -mouse_ndc.y, 0.0, 1.0}

    // Store computed mouse state.
    state.input.m_screen = linalg.array_cast(core.mouse_position(), int)
    state.input.m_world = linalg.array_cast(mouse_world.xy, int)

    // Simulate the player (physics, respond to user input, etc)
    player_update(state)

    // Draw the level colliders as lines.
    for c in level.colliders do line_renderer_append_rect(&state.line_renderer, c.rect, .DarkGray)
    line_renderer_append_rect(&state.line_renderer, level.rect, .White)

    // @(thread_local)
    // broad_count, max_broad_count: int
    // broad_count = 0

    // @(thread_local)
    // narrow_count, max_narrow_count: int
    // narrow_count = 0

    // contacts: [dynamic]^Collider
    // defer delete(contacts)

    // // Test for player collision.
    // ds.bvh_traverse_predicate(
    //     &level.colliders_bvh,
    //     // Branch visitor test.
    //     proc(rect: ds.BVH_Rect) -> bool {
    //         broad_count += 1
    //         hit := ds.rect_overlaps(app.state.player_rect, rect)
    //         line_renderer_append_rect(&app.state.line_renderer, rect, hit ? .Magenta : .Yellow)
    //         return hit
    //     },
    //     // Leaf visitor.
    //     proc(colliders: []Collider) {
    //         // Reach leaf node, test each item in the leaf.
    //         for c in colliders {
    //             hit := ds.rect_overlaps(app.state.player_rect, c.rect)
    //             line_renderer_append_rect(&app.state.line_renderer, c.rect, hit ? .Red : .Cyan)
    //             narrow_count += 1
    //         }
    //     },
    // )

    // max_broad_count = max(max_broad_count, broad_count)
    // max_narrow_count = max(max_narrow_count, narrow_count)

    // log.debugf("broad test: {} / {}", broad_count, max_broad_count)
    // log.debugf("narrow test: {} / {}", narrow_count, max_narrow_count)

    // // Test for player collision.
    // ds.bvh_traverse(&level.colliders_bvh, app.state.player_rect, proc(colliders: []Collider) {
    //     for c in colliders do if ds.rect_overlaps(app.state.player_rect, c.rect) {
    //         line_renderer_append_rect(&app.state.line_renderer, c.rect, .Red)
    //     }
    // })
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

player_update :: proc(state: ^AppState) {

    state.player.position = state.input.m_world
    state.player.size = {96, 96}

    // ...
    rect := make_rect(state.player.position, state.player.size)
    hit := check_collision(rect)

    sprite_renderer_append(&state.sprite_renderer, state.player.position - {16, 32}, state.sprites.tile)
    line_renderer_append_rect(&state.line_renderer, rect, hit ? .Red : .Yellow)
}

make_rect :: proc(pos, size: [2]int) -> [4]int {
    return {pos.x, pos.y, size.x, size.y}
}
