# Kinda mruby

`kinda_mruby` embeds the pinned mruby 4.0.0 runtime through Kinda. Each runtime
instance is independent; unlike MRI, mruby has no process-global VM lock.

The source archive is checksum-pinned and compiled locally so the NIF and the
static library always share the exact same mruby build configuration and value
layout. Ruby is a build-time dependency only.
