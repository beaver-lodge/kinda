# Kinda mruby

`kinda_mruby` embeds the pinned mruby 4.0.0 runtime through Kinda. Each runtime
instance is independent; unlike MRI, mruby has no process-global VM lock.

The source archive is checksum-pinned and compiled locally so the NIF and the
static library always share the exact same mruby build configuration and value
layout. Ruby is a build-time dependency only.

`Kinda.MRuby.VM` owns one `mrb_state`. Values retain a BEAM resource reference
to that VM and are explicitly rooted in mruby's GC. Closing a VM therefore
rejects new evaluation but defers `mrb_close` until every child has been
released, making explicit close and BEAM GC safe in either order. Every entry
into a VM is serialized and Ruby exceptions are contained with
`mrb_protect_error` before control returns to the NIF boundary.

Independent VMs run on dirty CPU schedulers and can execute concurrently;
calls into the same VM remain serialized. `Kinda.MRuby.Bytecode` compiles a
source program once into mruby's RITE format and owns the copied bytes without
retaining a compiler VM, so the program can be reused across isolated states.
