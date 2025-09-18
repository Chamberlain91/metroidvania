package metroidvania_game

import "base:intrinsics"
import "core:fmt"
import "core:log"
import "core:strconv"
import "core:strings"
import "deps:oak/core"
import "deps:oak/ds"
import "deps:oak/gpu"
import ldtk "deps:odin-ldtk"

Tile :: struct {
    image: ^gpu.Image,
}

Level :: struct {
    // Position of the level in the world (px).
    position:      [2]int,
    // Size of the level in the world (px).
    size:          [2]int,
    // Size of a tile in the level (px).
    tile_size:     int,
    // The integer representing the tile types.
    grid:          ds.Grid(int),
    // Tiles?
    // Entity Description
    colliders:     [dynamic]Collider,
    colliders_bvh: ds.BVH(Collider),
}

// Union? Box, Circle, Polygon(s)?
Collider :: struct {
    rect: [4]i32,
    id:   int,
}

levels: map[string]Level

project_init :: proc() {

    // Load the LDTK json.
    project, project_ok := ldtk.load_from_memory(#load("assets/project.ldtk"), context.temp_allocator).?
    log.assert(project_ok)

    // TODO: Extract, process, and store relevant level information.
    load_definitions(project)

    // Levels have tiles (visual)
    // Levels have collisions (solid, derived from tiles/intgrid?)
    // Levels have entities
    // Levels have fields

    // Entities are created and destroyed when transition between levels?
    // Entity state is stored and recovered?

    // Enter level -> level_enter(level: ^Level)
    // - spawn entities?
    // - restore state?

    // Exit level -> level_exit(level: ^Level)
    // - save state?
    // - destroy entities?

    // Create entity -> create_entity_instance(id, fields) -> ^Entity
    // - ???

    // Destroy entity -> destroy_entity(entity: ^Entity)
    // - ???

    // ...
    for l in project.levels {
        // l.uid
        // l.identifier
        // l.iid
        // l.world_depth
        // l.world_x
        // l.world_y
        // l.px_height
        // l.px_width
        // l.layer_instances
        // l.field_instances
        // l.neighbours

        level := Level {
            size     = {l.px_width, l.px_height},
            position = {l.world_x, l.world_y},
        }

        for f in l.field_instances {
            // f.def_uid
            // f.identifier
            // f.type
            // f.value
        }

        for a in l.layer_instances {
            // l.auto_layer_tiles
            // l.c_width, l.c_height
            // l.entity_instances
            // l.iid
            for e in a.entity_instances {
                // e.px, e.py
                // e.tags
                // e.identifier
                // e.def_uid
                // e.iid ???
                for f in e.field_instances {
                    // f.def_uid
                    // f.identifier
                    // f.type
                    // f.value
                }
            }

            if a.identifier == "solid" {

                level.tile_size = a.grid_size
                level.grid = ds.grid_create(int, {a.c_width, a.c_height})

                for v, i in a.int_grid_csv {

                    ix := i % a.c_width
                    iy := i / a.c_width

                    ds.grid_set(level.grid, {ix, iy}, v)

                    if v > 0 {
                        x := cast(i32)(ix * level.tile_size)
                        y := cast(i32)(iy * level.tile_size)
                        w := cast(i32)(level.tile_size)

                        collider := Collider {
                            rect = {x, y, w, w},
                            id   = len(level.colliders),
                        }

                        append(&level.colliders, collider)
                    }
                }
            }

            ds.bvh_build(&level.colliders_bvh, level.colliders[:], proc(c: Collider) -> ds.BVH_Rect {
                return c.rect
            })
        }

        levels[intern(l.identifier)] = level
    }

    for name in levels {
        log.debugf("Loaded level '{}'", name)
    }

    // Level
    // - exit connections
    // - solid layer
    // - tile layer
    // - entities

    // l:ldtk.Layer_Instance
    // t:ldtk.Tile_Instance
    // t.t // tile id
    // t.src //

    load_definitions :: proc(project: ldtk.Project) {

        // LOAD ENUM DEFINITIONS.
        load_enum_definitions(project)
        for def in _world.enums.definitions {
            validate_enum_definition(def)
        }

        // LOAD TILESET DEFINITIONS.
        for tileset in project.defs.tilesets {
            // tileset.identifier
            // tileset.uid
            // tileset.rel_path
        }
        // TODO: Validate desired tilesets are available?

        // LOAD LAYER DEFINITIONS.
        load_layer_definitions(project)
        // TODO: Validate layer definitions?

        // LOAD LEVEL DEFINITIONS.
        load_level_definitions(project)

        // LOAD ENTITY DEFINITIONS
        // load_entity_definitions(project)

        // TODO: Validate entity definitions?
        for def in _world.entity.definitions {
            log.debugf("Entity '{}' (Type: {})", def.identifier, def.type)
            log.debugf("- Tags : {}", def.tags)
            log.debugf("- Pivot: {}", def.pivot)
            if len(def.fields) > 0 {
                log.debug("- Fields:")
                for field in def.fields {
                    log.debugf("  - {}: {}", field.identifier, field.type)
                }
            }
        }
    }

    load_enum_definitions :: proc(project: ldtk.Project) {

        definitions: [dynamic]Enum_Definition
        reserve(&definitions, len(project.defs.enums))

        for d in project.defs.enums {

            values: [dynamic]string
            for v in d.values {
                append(&values, v.id)
            }

            definition := Enum_Definition {
                uid        = cast(Enum_UID)d.uid,
                identifier = d.identifier,
                values     = values[:],
                type       = get_registered_enum_type(d.identifier),
            }
            append(&definitions, definition)

            if definition.type == nil {
                log.warnf("Could not find registered enum type for '{}'", d.identifier)
            }
        }

        _world.enums.definitions = definitions[:]
        for &definition in definitions {
            _world.enums.uid_lookup[definition.uid] = &definition
        }
    }

    load_layer_definitions :: proc(project: ldtk.Project) {

        for layer in project.defs.layers {

            definition := Layer_Definition {
                uid = cast(Layer_UID)layer.uid,
                // TODO
            }
            _ = definition
        }
    }

    load_entity_definitions :: proc(project: ldtk.Project) {

        definitions: [dynamic]Entity_Definition
        reserve(&definitions, len(project.defs.entities))

        for def in project.defs.entities {

            fields: [dynamic]Field_Definition
            reserve(&fields, len(def.field_defs))

            for f in def.field_defs {

                field := Field_Definition {
                    uid        = cast(Field_UID)f.uid,
                    identifier = f.identifier,
                    type       = resolve_field_type(f.purple_type),
                    is_array   = f.is_array,
                }
                append(&fields, field)
            }

            meta := Entity_Definition {
                identifier = def.identifier,
                type       = get_registered_entity_type(def.identifier),
                tags       = def.tags,
                pivot      = {
                    cast(int)(def.pivot_x * cast(f32)def.width),
                    cast(int)(def.pivot_y * cast(f32)def.height),
                },
                size       = {def.width, def.height},
                fields     = fields[:],
            }
            append(&definitions, meta)

            if meta.type == nil {
                log.warnf("Could not find registered entity type for '{}'", def.identifier)
            }
        }

        _world.entity.definitions = definitions[:]
    }

    load_level_definitions :: proc(project: ldtk.Project) {

        for _ in project.defs.level_fields {
            // TODO
        }

        for _ in project.levels {

            // level.uid
            // level.identifier
            // level.iid
            // level.world_depth
            // level.world_x
            // level.world_y
            // level.px_height
            // level.px_width
            // level.layer_instances
            // level.field_instances
            // level.neighbours
        }
    }

    resolve_field_type :: proc(type: string) -> typeid {

        // F_Int, F_Float, F_string,
        // F_Text, F_Bool, F_Color, F_Enum(...),
        // F_Point, F_Path, F_EntityRef, F_Tile

        switch type {
        case "F_Int": return int
        case "F_Float": return f32
        case "F_String", "F_Text": return string
        case "F_Bool": return bool
        case "F_Point": return [2]int
        }

        // Resolve enum type.
        if strings.starts_with(type, "F_Enum(") {
            enum_id := cast(Enum_UID)(strconv.parse_int(type[7:len(type) - 1]) or_else 0)
            enum_ptr, enum_ok := _world.enums.uid_lookup[enum_id]
            if !enum_ok {
                log.panicf("Unable to resolve F_Enum type {}", type)
            } else {
                return enum_ptr.type
            }
        }

        log.panicf("Unimplemented purple type {}", type)
    }
}

destroy_project :: proc() {
    delete(_world.entity.types)
    delete(_world.entity.definitions)
}

project_register_entity :: proc($E: typeid, identifier: string = "") where intrinsics.type_is_struct(E) {
    // TODO: Validate subtype from Entity
    _world.entity.types[get_type_identifier(typeid_of(E))] = typeid_of(E)
}

@(private = "file")
get_registered_entity_type :: proc(identifier: string) -> typeid {
    return _world.entity.types[identifier] or_else nil
}

project_register_enum :: proc($E: typeid) where intrinsics.type_is_enum(E) {
    _world.enums.types[get_type_identifier(typeid_of(E))] = typeid_of(E)
}

@(private = "file")
get_type_identifier :: proc(type: typeid) -> string {
    str := strings.to_snake_case(fmt.tprint(type), context.temp_allocator)
    return intern(str)
}

@(private = "file")
get_registered_enum_type :: proc(identifier: string) -> typeid {
    return _world.enums.types[identifier] or_else nil
}

@(private = "file", disabled = !core.DEV_BUILD)
validate_enum_definition :: proc(def: Enum_Definition) {

    if def.type == nil {
        log.warnf("Enum '{}' is not associated with a type.", def.identifier)
    }

    log.debugf("Enum '{}' (UID: {}, Type: {})", def.identifier, def.uid, def.type)
    for value in def.values {
        log.debugf(" - {}", value)
    }

    // TODO: Validate enum values match the type (extras or missing).
}

@(private)
intern :: proc(str: string) -> string {
    return strings.intern_get(&_world.strs, str) or_else panic("Unable to intern string")
}

@(private = "file")
_world: struct {
    enums:  struct {
        types:       map[string]typeid,
        definitions: []Enum_Definition,
        uid_lookup:  map[Enum_UID]^Enum_Definition,
    },
    entity: struct {
        types:       map[string]typeid,
        definitions: []Entity_Definition,
    },
    strs:   strings.Intern,
}

Enum_UID :: distinct int

Enum_Definition :: struct {
    uid:        Enum_UID,
    identifier: string,
    values:     []string,
    type:       typeid,
}

// Entity meta information.
// This is like the "class" of an entity.
Entity_Definition :: struct {
    identifier: string,
    type:       typeid, // ???
    tags:       []string,
    pivot:      [2]int,
    size:       [2]int,
    fields:     []Field_Definition,
}

Field_UID :: distinct int

Field_Definition :: struct {
    uid:        Field_UID,
    identifier: string,
    type:       Field_Type,
    is_array:   bool,
}

// F_Int, F_Float, F_String,
// F_Text, F_Bool, F_Color, F_Enum(...),
// F_Point, F_Path, F_EntityRef, F_Tile
Field_Type :: union {
    typeid,
    ^Enum_Definition,
}

Field_Integer :: int
Field_Float :: f32
Field_Boolean :: bool
Field_String :: string // Aliased with F_Text and F_Path
Field_Color :: [4]f32
Field_Enum :: distinct int // TODO: Enum_UID ?
Field_Point :: [2]int
// Field_EntityRef :: ???
// Field_Tile :: ???

Field_Value :: union {
    Field_Integer,
    Field_Float,
    Field_Boolean,
    Field_String,
    Field_Color,
    Field_Enum,
    Field_Point,
}

Tileset_UID :: distinct int

// TODO: Tileset_Definition

Layer_UID :: distinct int

Layer_Definition :: struct {
    uid:              Layer_UID,
    identifier:       string,
    offset:           [2]int,
    grid_size:        int, // ?
    parallax:         struct {
        factor:  [2]f32,
        scaling: bool,
    },
    opacity:          f32,
    type:             Layer_Type,
    int_values:       []Int_Grid_Value_Definition,
    int_groups:       []Int_Grid_Group_Definition,
    auto_tileset_uid: Tileset_UID,
    auto_source_uid:  Layer_UID, // ???
}

Layer_Type :: enum {
    Int_Grid,
    Entity,
    Tiles,
    Auto_Layer,
}

Layer_Int_Grid_Group_UID :: distinct int

Int_Grid_Group_Definition :: struct {
    uid:        Layer_Int_Grid_Group_UID,
    identifier: string,
}

Int_Grid_Value_Definition :: struct {
    identifier: string,
    // Parent group (0 means no group).
    group_uid:  Layer_Int_Grid_Group_UID,
    value:      int,
}

// -----------------------------------------------------------------------------

// An instance of an entity.
Entity :: struct {
    meta:     ^Entity_Definition,
    position: [2]f32,
    size:     [2]f32,
}

Neighbor_Direction :: enum {
    Unknown,
    North,
    North_East,
    East,
    South_East,
    South,
    South_West,
    West,
    North_West,
}

@(private = "file")
get_neighbor_dir :: proc(dir: string) -> Neighbor_Direction {
    switch dir {
    case "n": return .North
    case "ne": return .North_East
    case "e": return .East
    case "se": return .South_East
    case "s": return .South
    case "sw": return .South_West
    case "w": return .West
    case "nw": return .North_West
    case: return .Unknown
    }
}
