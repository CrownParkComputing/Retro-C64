cmake_minimum_required(VERSION 3.22.1)

project(vicecore_android C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

if(NOT ANDROID)
    message(FATAL_ERROR
        "This CMakeLists is for Android only. Configure with the NDK's "
        "toolchain file, e.g.:\n"
        "  cmake -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake "
        "-DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 "
        "-DCMAKE_BUILD_TYPE=Release ..")
endif()

# VICE_SRC points at the shared VICE source checkout (same tree used by
# VICEAndroid); this project does not vendor its own copy. VICE_BUILD_DIR
# is the pre-existing Android arm64 headless cross-build produced by
# ~/AndroidStudioProjects/VICEAndroid/tools/build-vice-android-headless.sh
# -- we reuse its .o/.a output, we do not rebuild VICE from this file.
if(NOT DEFINED VICE_SRC)
    set(VICE_SRC "$ENV{HOME}/AndroidStudioProjects/VICE-source/vice-3.10")
endif()
if(NOT DEFINED VICE_BUILD_DIR)
    set(VICE_BUILD_DIR "${VICE_SRC}/build-android-arm64-headless")
endif()
set(VICE_SRC_DIR "${VICE_SRC}/src")

if(NOT EXISTS "${VICE_BUILD_DIR}/src/x64sc")
    message(FATAL_ERROR
        "VICE Android headless build not found at ${VICE_BUILD_DIR}. Run "
        "~/AndroidStudioProjects/VICEAndroid/tools/build-vice-android-headless.sh "
        "first (see VICE_SRC/VICE_BUILD_DIR to override the source/build "
        "locations).")
endif()

# Same base object list as native/vice_core/linux/CMakeLists.txt and
# VICEAndroid/app/src/main/cpp/CMakeLists.txt.
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

# Same c64sc (game machine) static lib set as VICEAndroid/app/src/main/cpp/CMakeLists.txt.
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

find_library(LOG_LIB log)
find_library(AAUDIO_LIB aaudio)
find_library(ANDROID_LIB android)

# resid/libsid are C++ (reSID), but vice_bridge.c / vice_vsid_bridge.c are
# plain C, so this project doesn't enable the CXX language and CMake won't
# auto-select a C++ link driver or auto-link libc++ for us -- do it by hand
# with the NDK's static libc++ (matches VICEAndroid's ANDROID_STL=c++_static).
# NOTE: don't use find_library() for these -- it also matches the *host*
# libc++abi.a under toolchains/llvm/prebuilt/linux-x86_64/lib/ (built for
# the build machine, not the target), which links but is architecture-
# incompatible ("is incompatible with aarch64linux"). Go straight to the
# target sysroot instead, same place the NDK toolchain file points clang at.
set(CXX_STATIC_LIB "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-android/libc++_static.a")
set(CXX_ABI_LIB "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-android/libc++abi.a")
if(NOT EXISTS "${CXX_STATIC_LIB}")
    message(FATAL_ERROR "libc++_static.a not found at ${CXX_STATIC_LIB}")
endif()
set(CXX_RUNTIME_LIBS ${CXX_STATIC_LIB} ${CXX_ABI_LIB})

add_library(vicecore SHARED
        "${CMAKE_CURRENT_SOURCE_DIR}/../bridge/vice_bridge.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/../bridge/audio_backend_android.c"
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
        "${VICE_SRC_DIR}/tapeport")

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
        ${CXX_RUNTIME_LIBS}
        -Wl,--end-group
        z
        m
        ${AAUDIO_LIB}
        ${ANDROID_LIB}
        ${LOG_LIB})

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
        "${VICE_BUILD_DIR}/src/arch/shared/libarchdep.a")

set(VICE_AVAILABLE_VSID_LIBS)
foreach(vice_static_lib ${VICE_VSID_STATIC_LIBS})
    if(EXISTS "${vice_static_lib}")
        list(APPEND VICE_AVAILABLE_VSID_LIBS "${vice_static_lib}")
    endif()
endforeach()

if(EXISTS "${VICE_BUILD_DIR}/src/c64/libvsid.a")
    add_library(vicecore_vsid SHARED
            "${CMAKE_CURRENT_SOURCE_DIR}/../bridge/vice_vsid_bridge.c"
            "${CMAKE_CURRENT_SOURCE_DIR}/../bridge/audio_backend_android.c"
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
            "${VICE_SRC_DIR}/tapeport")

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
            ${CXX_RUNTIME_LIBS}
            -Wl,--end-group
            z
            m
            ${AAUDIO_LIB}
            ${ANDROID_LIB}
            ${LOG_LIB})
else()
    message(WARNING "libvsid.a not found under ${VICE_BUILD_DIR}; skipping vicecore_vsid target")
endif()
