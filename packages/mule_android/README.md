# Android compartido

Única implementación de los canales nativos de guardado público y recepción de archivos. Los proyectos Android agregan este directorio Kotlin a su source set; sus MainActivity son adaptadores de ciclo de vida. No es otro APK ni otro servicio remoto.

La recepción copia permisos URI a una bandeja privada. La autorización para importar depende del módulo de perfiles en Dart y se verifica en el servicio de recepción. La escritura pública conserva MediaStore y el flujo de permisos existente.
