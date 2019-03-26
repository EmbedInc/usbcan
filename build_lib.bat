@echo off
rem
rem   BUILD_LIB [-dbg]
rem
rem   Build the USBCAN library.
rem
setlocal
call build_pasinit

call src_insall %srcdir% %libname%

call src_pas %srcdir% %libname%_devs %1
call src_pas %srcdir% %libname%_frame %1
call src_pas %srcdir% %libname%_in %1
call src_pas %srcdir% %libname%_open %1
call src_pas %srcdir% %libname%_out %1
call src_pas %srcdir% %libname%_sys %1
call src_c   %srcdir% %libname%_sysc %1

call src_lib %srcdir% %libname%
call src_msg %srcdir% %libname%
