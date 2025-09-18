package metroidvania_game

import "deps:oak/gpu"

Line_Renderer :: struct {
    instances: [dynamic]Line_Instance,
}

Line_Buffer :: struct {
    lines: [0]Line_Instance,
}

Line_Instance :: struct {
    points: [2]gpu.vec2,
    color:  gpu.vec4,
}

Line_Push_Constants :: struct {
    camera_matrix: gpu.mat4x4,
    line_buffer:   gpu.Buffer_Reference(Line_Buffer),
}

line_renderer_clear :: proc(renderer: ^Line_Renderer) {
    clear(&renderer.instances)
}

line_renderer_append :: proc(renderer: ^Line_Renderer, a, b: [2]int, color: Line_Color, loc := #caller_location) {
    @(static, rodata)
    Line_Colors := [Line_Color]gpu.vec4 {
        .White   = {1.0, 1.0, 1.0, 1.0},
        .Black   = {0.0, 0.0, 0.0, 1.0},
        .Red     = {1.0, 0.0, 0.0, 1.0},
        .Green   = {0.0, 1.0, 0.0, 1.0},
        .Blue    = {0.0, 0.0, 1.0, 1.0},
        .Cyan    = {0.0, 1.0, 1.0, 1.0},
        .Magenta = {1.0, 0.0, 1.0, 1.0},
        .Yellow  = {1.0, 1.0, 0.0, 1.0},
        .Gray    = {0.5, 0.5, 0.5, 1.0},
    }

    instance := Line_Instance {
        points = {     //
            0 = {cast(f32)a.x, cast(f32)a.y},
            1 = {cast(f32)b.x, cast(f32)b.y},
        },
        color = Line_Colors[color],
    }
    append(&renderer.instances, instance)
}

line_renderer_append_rect :: proc(renderer: ^Line_Renderer, rect: [4]int, color: Line_Color, loc := #caller_location) {

    L, T, R, B := rect.x, rect.y, (rect.x + rect.z), (rect.y + rect.w)

    q0 := [2]int{L, T}
    q1 := [2]int{R, T}
    q2 := [2]int{R, B}
    q3 := [2]int{L, B}

    line_renderer_append(renderer, q0, q1, color, loc = loc)
    line_renderer_append(renderer, q1, q2, color, loc = loc)
    line_renderer_append(renderer, q2, q3, color, loc = loc)
    line_renderer_append(renderer, q3, q0, color, loc = loc)
}

@(require_results)
line_renderer_to_buffer :: proc(renderer: ^Line_Renderer) -> ^gpu.Buffer {
    if count := len(renderer.instances); count > 0 {
        buffer := gpu.create_buffer(size_of(Line_Instance) * count)
        gpu.copy(buffer, 0, renderer.instances[:])
        gpu.memory_barrier() // TODO: Narrow to host memory
        return buffer
    } else {
        // No instances, no buffer
        return nil
    }
}

Line_Color :: enum {
    White,
    Black,
    Red,
    Green,
    Blue,
    Cyan,
    Magenta,
    Yellow,
    Gray,
}
