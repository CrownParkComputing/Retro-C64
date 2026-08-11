cmake_minimum_required(VERSION 3.16)

project(vicecore C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

# VICE_SRC points at the shared VICE source checkout (same tree used by
# VICEAndroid); this project does not vendor its own copy.
if(NOT DEFINED VICE_SRC)
    set(VICE_SRC "$ENV{HOME}/AndroidStudioProjects/VICE-source/vice-3.10")
endif()
if(NOT DEFINED VICE_BUILD_DIR)
    set(VICE_BUILD_DIR "${VICE_SRC}/build-linux-x64-headless")
endif()
set(VICE_SRC_DIR "${VICE_SRC}/src")

if(NOT EXISTS "${VICE_BUILD_DIR}/src/x64sc")
    message(FATAL_ERROR
        "VICE headless build not found at ${VICE_BUILD_DIR}. Run "
        "linux/build-vice-linux-headless.sh first (see VICE_SRC/VICE_BUILD_DIR "
        "to override the source/build locations).")
endif()

# Same base object list as VICEAndroid/app/src/main/cpp/CMakeLists.txt.
set(VICE_BASE_OBJECT_NAMES
        alarm attach autostart autostart-prg cbmdos cbmimage charset clipboard
        cmdline color crc32 crt debug dma event findpath fliplist gcr info init
        initcmdline interrupt kbdbuf keyboard keymap lib log machine-bus machine
        main mainlock m3u network opencbmlib palette profiler ram rawfile rawnet
        resources romset screenshot sha1 snapshot socket sound sysfile traps util
        vicefeatures vsync zfile zipcode midi)

set(VICE_BASE_OBJECTS)
foreach(obj ${VICE_BASE_OBJECT_NAMES})
    list(APPEND VICE_BASE_OBJECTS "${VICE_BUILD_DIR}/src/${obj}.o")
endforeach()

# Same c64sc (game machine) static lib set as the Android build.
set(VICE_STATIC_LIBS
        "${VICE_BUILD_DIR}/src/arch/shared/libarchdep.a"
        "${VICE_BUILD_DIR}/src/tapeport/libtapeport.a"
        "${VICE_BUILD_DIR}/src/c64/libc64sc.a"
        "${VICE_BUILD_DIR}/src/c64/cart/libc64cartsystem.a"
        "${VICE_BUILD_DIR}/src/c64/cart/libc64cart.a"
        "${VICE_BUILD_DIR}/src/c64/cart/libc64commoncart.a"
        "${VICE_BUILD_DIR}/src/datasette/libdatasette.a"
        "${VICE_BUILD_DIR}/src/drive/iec/libdriveiec.a"
        "${VICE_BUILD_DIR}/src/drive/iecieee/libdriveiecieee.a"
        "${VICE_BUILD_DIR}/src/drive/iec/c64exp/libdriveiecc64exp.a"
        "${VICE_BUILD_DIR}/src/drive/ieee/libdriveieee.a"
        "${VICE_BUILD_DIR}/src/drive/libdrive.a"
        "${VICE_BUILD_DIR}/src/drive/tcbm/libdrivetcbm.a"
        "${VICE_BUILD_DIR}/src/lib/p64/libp64.a"
        "${VICE_BUILD_DIR}/src/iecbus/libiecbus.a"
        "${VICE_BUILD_DIR}/src/parallel/libparallel.a"
        "${VICE_BUILD_DIR}/src/vdrive/libvdrive.a"
        "${VICE_BUILD_DIR}/src/sid/libsid.a"
        "${VICE_BUILD_DIR}/src/resid/libresid.a"
        "${VICE_BUILD_DIR}/src/resid-dtv/libresiddtv.a"
        "${VICE_BUILD_DIR}/src/monitor/libmonitor.a"
        "${VICE_BUILD_DIR}/src/joyport/libjoyport.a"
        "${VICE_BUILD_DIR}/src/samplerdrv/libsamplerdrv.a"
        "${VICE_BUILD_DIR}/src/arch/shared/sounddrv/libsounddrv.a"
        "${VICE_BUILD_DIR}/src/arch/shared/mididrv/libmididrv.a"
        "${VICE_BUILD_DIR}/src/arch/shared/socketdrv/libsocketdrv.a"
        "${VICE_BUILD_DIR}/src/arch/shared/hwsiddrv/libhwsiddrv.a"
        "${VICE_BUILD_DIR}/src/gfxoutputdrv/libgfxoutputdrv.a"
        "${VICE_BUILD_DIR}/src/printerdrv/libprinterdrv.a"
        "${VICE_BUILD_DIR}/src/diskimage/libdiskimage.a"
        "${VICE_BUILD_DIR}/src/fsdevice/libfsdevice.a"
        "${VICE_BUILD_DIR}/src/tape/libtape.a"
        "${VICE_BUILD_DIR}/src/fileio/libfileio.a"
        "${VICE_BUILD_DIR}/src/serial/libserial.a"
        "${VICE_BUILD_DIR}/src/core/libcore.a"
        "${VICE_BUILD_DIR}/src/rs232drv/librs232drv.a"
        "${VICE_BUILD_DIR}/src/viciisc/libviciisc.a"
        "${VICE_BUILD_DIR}/src/raster/libraster.a"
        "${VICE_BUILD_DIR}/src/userport/libuserport.a"
        "${VICE_BUILD_DIR}/src/diag/libdiag.a"
        "${VICE_BUILD_DIR}/src/core/rtc/librtc.a"
        "${VICE_BUILD_DIR}/src/video/libvideo.a"
        "${VICE_BUILD_DIR}/src/arch/headless/libarch.a"
        "${VICE_BUILD_DIR}/src/imagecontents/libimagecontents.a"
        "${VICE_BUILD_DIR}/src/c64/libc64scstubs.a"
        "${VICE_BUILD_DIR}/src/hvsc/libhvsc.a"
        "${VICE_BUILD_DIR}/src/lib/libzmbv/libzmbv.a"
        "${VICE_BUILD_DIR}/src/arch/shared/libarchdep.a"
        "${VICE_BUILD_DIR}/src/lib/linenoise-ng/liblinenoiseng.a")

set(VICE_AVAILABLE_STATIC_LIBS)
foreach(vice_static_lib ${VICE_STATIC_LIBS})
    if(EXISTS "${vice_static_lib}")
        list(APPEND VICE_AVAILABLE_STATIC_LIBS "${vice_static_lib}")
    endif()
endforeach()

find_package(PkgConfig REQUIRED)
pkg_check_modules(ALSA REQUIRED alsa)
find_package(Threads REQUIRED)

add_library(vicecore SHARED
        "${CMAKE_CURRENT_SOURCE_DIR}/../bridge/vice_bridge.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/../bridge/audio_backend.c"
        ${VICE_BASE_OBJECTS})

target_include_directories(vicecore PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/../bridge"
        "${VICE_BUILD_DIR}/src"
        "${VICE_SRC_DIR}"
        "${VICE_SRC_DIR}/arch/headless"
        "${VICE_SRC_DIR}/arch/shared"
        "${VICE_SRC_DIR}/arch"
        "${VICE_SRC_DIR}/c64"
        "${VICE_SRC_DIR}/datasette"
        "${VICE_SRC_DIR}/drive"
        "${VICE_SRC_DIR}/monitor"
        "${VICE_SRC_DIR}/tape"
        "${VICE_SRC_DIR}/tapeport"
        ${ALSA_INCLUDE_DIRS})

target_link_options(vicecore PRIVATE
        -Wl,--wrap=archdep_init
        -Wl,--wrap=log_init
        -Wl,--wrap=video_init
        -Wl,--wrap=init_main
        -Wl,--wrap=video_canvas_create
        -Wl,--wrap=video_canvas_can_resize
        -Wl,--wrap=video_canvas_resize
        -Wl,--wrap=video_canvas_refresh
        -Wl,--wrap=sound_init_dummy_device
        -Wl,--wrap=vsync_do_vsync
        -Wl,--wrap=maincpu_mainloop)

target_link_libraries(vicecore
        -Wl,--start-group
        ${VICE_AVAILABLE_STATIC_LIBS}
        -Wl,--end-group
        z
        m
        stdc++
        ${ALSA_LIBRARIES}
        Threads::Threads)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")

add_executable(vice_smoke_test test/smoke_test.c)
target_include_directories(vice_smoke_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../bridge")
target_link_libraries(vice_smoke_test vicecore Threads::Threads dl)

add_executable(vice_audio_tone_test test/audio_tone_test.c)
target_include_directories(vice_audio_tone_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../bridge")
target_link_libraries(vice_audio_tone_test vicecore Threads::Threads dl m)

# Media hot-swap + machine snapshot save/restore, checked against the
# framebuffer rather than return codes alone (see the file header).
add_executable(vice_swap_snapshot_test test/swap_snapshot_test.c)
target_include_directories(vice_swap_snapshot_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../bridge")
target_link_libraries(vice_swap_snapshot_test vicecore Threads::Threads dl m)

# Proves vice_core_joystick()'s port argument selects the real C64 port.
add_executable(vice_joystick_port_test test/joystick_port_test.c)
target_include_directories(vice_joystick_port_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../bridge")
target_link_libraries(vice_joystick_port_test vicecore Threads::Threads dl m)

# --------------------------------------------------------------------------
# vsid (standalone SID-file player machine) — same idea as vicecore above,
# but linking libvsid.a/libvsidstubs.a instead of libc64sc.a, per
# VICEAndroid/app/src/main/cpp/CMakeLists_vsid.txt. vsid runs with video
# disabled, so it needs no video_canvas_* wraps.
# --------------------------------------------------------------------------

set(VICE_VSID_STATIC_LIBS
        "${VICE_BUILD_DIR}/src/arch/shared/libarchdep.a"
        "${VICE_BUILD_DIR}/src/c64/libvsid.a"
        "${VICE_BUILD_DIR}/src/c64/libvsidstubs.a"
        "${VICE_BUILD_DIR}/src/sid/libsid.a"
        "${VICE_BUILD_DIR}/src/resid/libresid.a"
        "${VICE_BUILD_DIR}/src/resid-dtv/libresiddtv.a"
        "${VICE_BUILD_DIR}/src/monitor/libmonitor.a"
        "${VICE_BUILD_DIR}/src/arch/shared/sounddrv/libsounddrv.a"
        "${VICE_BUILD_DIR}/src/arch/shared/mididrv/libmididrv.a"
        "${VICE_BUILD_DIR}/src/arch/shared/socketdrv/libsocketdrv.a"
        "${VICE_BUILD_DIR}/src/arch/shared/hwsiddrv/libhwsiddrv.a"
        "${VICE_BUILD_DIR}/src/serial/libserial.a"
        "${VICE_BUILD_DIR}/src/core/libcore.a"
        "${VICE_BUILD_DIR}/src/vicii/libvicii.a"
        "${VICE_BUILD_DIR}/src/c64/cart/libc64cartsystem.a"
        "${VICE_BUILD_DIR}/src/c64/cart/libc64cart.a"
        "${VICE_BUILD_DIR}/src/c64/cart/libc64commoncart.a"
        "${VICE_BUILD_DIR}/src/lib/md5/libmd5.a"
        "${VICE_BUILD_DIR}/src/raster/libraster.a"
        "${VICE_BUILD_DIR}/src/video/libvideo.a"
        "${VICE_BUILD_DIR}/src/joyport/libjoyport.a"
        "${VICE_BUILD_DIR}/src/hvsc/libhvsc.a"
        "${VICE_BUILD_DIR}/src/datasette/libdatasette.a"
        "${VICE_BUILD_DIR}/src/arch/headless/libarch.a"
        "${VICE_BUILD_DIR}/src/imagecontents/libimagecontents.a"
        "${VICE_BUILD_DIR}/src/lib/libzmbv/libzmbv.a"
        "${VICE_BUILD_DIR}/src/samplerdrv/libsamplerdrv.a"
        "${VICE_BUILD_DIR}/src/lib/linenoise-ng/liblinenoiseng.a")

set(VICE_AVAILABLE_VSID_LIBS)
foreach(vice_static_lib ${VICE_VSID_STATIC_LIBS})
    if(EXISTS "${vice_static_lib}")
        list(APPEND VICE_AVAILABLE_VSID_LIBS "${vice_static_lib}")
    endif()
endforeach()

if(EXISTS "${VICE_BUILD_DIR}/src/c64/libvsid.a")
    add_library(vicecore_vsid SHARED
            "${CMAKE_CURRENT_SOURCE_DIR}/../bridge/vice_vsid_bridge.c"
            "${CMAKE_CURRENT_SOURCE_DIR}/../bridge/audio_backend.c"
            ${VICE_BASE_OBJECTS})

    target_include_directories(vicecore_vsid PRIVATE
            "${CMAKE_CURRENT_SOURCE_DIR}/../bridge"
            "${VICE_BUILD_DIR}/src"
            "${VICE_SRC_DIR}"
            "${VICE_SRC_DIR}/arch/headless"
            "${VICE_SRC_DIR}/arch/shared"
            "${VICE_SRC_DIR}/arch"
            "${VICE_SRC_DIR}/c64"
            "${VICE_SRC_DIR}/datasette"
            "${VICE_SRC_DIR}/drive"
            "${VICE_SRC_DIR}/monitor"
            "${VICE_SRC_DIR}/tape"
            "${VICE_SRC_DIR}/tapeport"
            ${ALSA_INCLUDE_DIRS})

    target_link_options(vicecore_vsid PRIVATE
            -Wl,--wrap=archdep_init
            -Wl,--wrap=log_init
            -Wl,--wrap=video_init
            -Wl,--wrap=init_main
            -Wl,--wrap=sound_init_dummy_device
            -Wl,--wrap=vsync_do_vsync
            -Wl,--wrap=maincpu_mainloop)

    target_link_libraries(vicecore_vsid
            -Wl,--start-group
            ${VICE_AVAILABLE_VSID_LIBS}
            -Wl,--end-group
            z
            m
            stdc++
            ${ALSA_LIBRARIES}
            Threads::Threads)

    add_executable(vice_vsid_smoke_test test/vsid_smoke_test.c)
    target_include_directories(vice_vsid_smoke_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../bridge")
    target_link_libraries(vice_vsid_smoke_test vicecore_vsid Threads::Threads dl)

    add_executable(vice_vsid_hotswap_test test/vsid_hotswap_test.c)
    target_include_directories(vice_vsid_hotswap_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../bridge")
    target_link_libraries(vice_vsid_hotswap_test vicecore_vsid Threads::Threads dl)

    add_executable(vice_vsid_rapid_swap_test test/vsid_rapid_swap_test.c)
    target_include_directories(vice_vsid_rapid_swap_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../bridge")
    target_link_libraries(vice_vsid_rapid_swap_test vicecore_vsid Threads::Threads dl)
else()
    message(WARNING "libvsid.a not found under ${VICE_BUILD_DIR}; skipping vicecore_vsid target")
endif()

# --------------------------------------------------------------------------
# sdl_viewer - SDL3 debug viewer. dlopen()s libvicecore.so / libvicecore_vsid.so
# at runtime (see viewer/sdl_viewer.c for why it never links either directly);
# only needs dl + SDL3 at link time.
# --------------------------------------------------------------------------

pkg_check_modules(SDL3 REQUIRED sdl3)

add_executable(sdl_viewer viewer/sdl_viewer.c)
target_include_directories(sdl_viewer PRIVATE ${SDL3_INCLUDE_DIRS})
target_link_directories(sdl_viewer PRIVATE ${SDL3_LIBRARY_DIRS})
target_link_libraries(sdl_viewer ${SDL3_LIBRARIES} dl)
target_compile_options(sdl_viewer PRIVATE ${SDL3_CFLAGS_OTHER})
