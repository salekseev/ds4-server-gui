// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DS4MacOS",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DS4MacOS", targets: ["DS4MacOS"])
    ],
    targets: [
        // C/ObjC engine: pristine upstream (submodule) + local embed wrapper
        .target(
            name: "ds4engine",
            path: "ds4-engine",
            // Keep in sync with the ds4-server link line in upstream/Makefile.
            // upstream/ds4_server.c is NOT listed: it compiles via #include in embed/ds4_server_embed.c
            sources: [
                "embed/ds4_server_embed.c",
                "upstream/ds4.c",
                "upstream/ds4_ssd.c",
                "upstream/ds4_distributed.c",
                "upstream/ds4_metal.m",
                "upstream/ds4_help.c",
                "upstream/ds4_kvstore.c",
                "upstream/rax.c",
                "upstream/ds4_layer_pack.c",
                "upstream/ds4_tp.c",
                "upstream/ds4_gpu_args.c",
            ],
            resources: [
                .copy("upstream/metal"),
            ],
            publicHeadersPath: "embed/include",
            cSettings: [
                .define("DS4_SERVER_TEST_NO_MAIN"),
                .headerSearchPath("upstream"),
                .unsafeFlags([
                    "-O3", "-ffast-math", "-mcpu=native",
                    "-Wall", "-Wextra", "-std=gnu99", // gnu99, not c99: upstream ds4_metal.m uses GNU typeof()
                    "-Wno-unused-parameter", "-Wno-unused-variable",
                    "-Wno-sign-compare",
                ]),
            ],
            swiftSettings: [],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedLibrary("m"),
                .linkedLibrary("pthread"),
            ]
        ),
        // Swift 菜单栏应用
        .executableTarget(
            name: "DS4MacOS",
            dependencies: ["ds4engine"],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DS4MacOSTests",
            dependencies: ["DS4MacOS"],
            path: "Tests"
        )
    ]
)
