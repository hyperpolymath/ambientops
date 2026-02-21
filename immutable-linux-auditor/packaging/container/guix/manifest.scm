(use-modules (gnu packages)
             (gnu packages base)
             (gnu packages cmake)
             (gnu packages gcc)
             (gnu packages pkg-config)
             (gnu packages rust)
             (gnu packages version-control)
             (gnu packages ninja)
             (gnu packages qt))

(packages->manifest
 (list cmake
       ninja
       gcc-toolchain
       pkg-config
       git
       rust
       qtbase
       qtdeclarative
       qtquickcontrols2))
