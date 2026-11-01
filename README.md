# ACS Drift by Water - menu (codigo fuente modular)

CSP carga un script online desde una sola URL, asi que se trabaja en varios ficheros
y se empaquetan en uno solo antes de subirlo.

Los textos del menu se mantienen en `src/i18n.lua`. Actualmente hay ingles (idioma
predeterminado) y espanol; se puede cambiar en la pestana Ajustes. CSP no expone en su
API Lua documentada el idioma de la instalacion, por lo que la seleccion es manual y
dura mientras esta cargado el script.
