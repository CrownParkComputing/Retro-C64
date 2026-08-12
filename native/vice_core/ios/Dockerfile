# Build environment for the iOS native core.
#
# mobaiapp/iosbox supplies the cross toolchain (clang targeting
# arm64-apple-ios, ld64.lld) and Flutter; it does not carry the few host build
# tools VICE's configure insists on. flex and bison generate the monitor's
# lexer/parser and run on the *host*, so they are ordinary amd64 packages --
# nothing here targets iOS.
FROM mobaiapp/iosbox:latest

RUN apt-get update \
    && apt-get install -y --no-install-recommends flex bison file \
    && rm -rf /var/lib/apt/lists/*
