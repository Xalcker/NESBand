# NESBand

- **Paridad entre versiones:** al terminar una mejora, actualiza `docs/paridad.md` (la fila y la columna NES) y anota en
  "Pendientes por versión" lo que falta en GB (`../GBBand`) y GEN (`../GENBand`).
- **Pruebas:** `uv run nesband test [--no-build] [--rapida] [-j N] [--lista] [patron]` (MAME con `tests/mame_shim.lua`; igual en macOS y Windows;
  `--emulador mesen` para Mesen `--testrunner`; `--sin-ventana` = MAME invisible). Es el corredor de `bandcore.testrun`, el mismo
  comando en los cuatro juegos. Los casos se llaman `cancion/caso`.
