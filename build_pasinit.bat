@echo off
rem
rem   Set up for building a Pascal module.
rem
call build_vars

call src_get %srcdir% %libname%.ins.pas
call src_get %srcdir% %libname%2.ins.pas

call src_get %srcdir% %libname%_driver.h
copya %libname%_driver.h (cog)lib/%libname%_driver.h

call src_go %srcdir%
call src_getfrom sys base.ins.pas
call src_getfrom sys sys.ins.pas
call src_getfrom util util.ins.pas
call src_getfrom string string.ins.pas
call src_getfrom file file.ins.pas
call src_getfrom pic pic.ins.pas
call src_getfrom can can.ins.pas
call src_getfrom can can3.ins.pas

copya (cog)lib/%libname%_driver.h
copya (cog)lib/sys.h
copya (cog)lib/util.h
copya (cog)lib/string.h
copya (cog)lib/file.h
copya (cog)lib/can.h
copya (cog)lib/can3.h

call src_builddate "%srcdir%"
