package metroidvania_game_build

import "../../deps/oak/build"

main :: proc() {

    app := build.Package {
        path        = "src",
        name        = "metroidvania",
        collections = {{"oak", "deps/oak"}},
    }

    // Run the app in BUILD_SHADERS mode to generate GLSL from Odin RTTI.
    if _, ok := build.run_executable(app, optimize = false, defines = {{"BUILD_SHADERS", true}}); !ok {
        build.fatal("Unable to generate shader.")
    }

    // Attempt to compile each shader in the shaders directory.
    if !build.compile_shaders_in_directory("src/shaders", "src/assets/shaders", .HLSL) {
        build.fatal("Unable to compile shader.")
    }

    // Either build or run.
    if build.args.run do build.run_executable(app)
    else do build.build_executable(app)

    // TODO: synchronize executables with `.vscode/launch.json`?
    // build.update_vscode_launch_json()

    // TODO: synchronize with `ols.json`?
    // build.update_ols_json()
}
