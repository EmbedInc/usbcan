{   System-dependent routines that do not need to access the native system
*   include files, but that do need to access system-dependent resources
*   from the Pascal environment.
*
*   This version is for Windows 2000 and later.
}
module usbcan_sys;
define usbcan_sys_open_name;
define usbcan_sys_read;
define usbcan_sys_write;
%include 'usbcan2.ins.pas';
%include 'sys_sys2.ins.pas';

type
  conn_data_t = record                 {private data per device connection}
    hout: sys_sys_file_conn_t;         {handle to bulk data output pipe}
    hin: sys_sys_file_conn_t;          {handle to bulk data input pipe}
    ovl_out: overlap_t;                {overlapped I/O descriptor for output}
    ovl_in: overlap_t;                 {overlapped I/O descriptor for input}
    name: string_var80_t;              {user name of the device}
    end;
  conn_data_p_t = ^conn_data_t;

procedure usbcan_sys_close (           {private close routine for device connection}
  in      conn_p: file_conn_p_t);      {pointer to connection to close}
  val_param; forward;
{
*   Define the interface exported by USBCAN_SYSC.C.  This contains routines
*   written in C to be able to use the Microsoft include files directly.
*   The routines defined below are a extension to this module implemented in
*   another file, and should be considered private to this module.
}
procedure usbcan_sys_open (            {open I/O handles given device info}
  in      dev: usbcan_dev_t;           {info about device to open}
  out     hout: sys_sys_file_conn_t;   {handle to write pipe connection}
  out     hin: sys_sys_file_conn_t;    {handle to read pipe connection}
  out     stat: sys_err_t);
  val_param; extern;
{
********************************************************************************
*
*   Subroutine USBCAN_SYS_OPEN_NAME (NAME, CONN, STAT)
*
*   Open a exclusive application-level connection to the USBCAN device with the
*   user-definable name NAME.  If NAME is empty, then the first unused device
*   found is opened, which makes the choice arbitrary if more than one unused
*   device is available.
}
procedure usbcan_sys_open_name (       {open connection to named USBCAN device}
  in      name: univ string_var_arg_t; {name of device to open, opens first on empty}
  out     conn: file_conn_t;           {returned connection to the device}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  devs: usbcan_devs_t;                 {list of devices that can be enumerated}
  dev_p: usbcan_dev_p_t;               {pointer to current devices list entry}
  hout, hin: sys_sys_file_conn_t;      {system handles to input and output pipes}
  dat_p: conn_data_p_t;                {pointer to our private connection data}
  busy: boolean;                       {device found but was busy}

label
  next_dev, opened, abort1, abort2;

begin
  conn.fnam.max := size_char(conn.fnam.str); {init var strings in CONN}
  conn.gnam.max := size_char(conn.gnam.str);
  conn.tnam.max := size_char(conn.tnam.str);

  usbcan_devs_get (util_top_mem_context, devs); {make list of connected devices}
  busy := false;                       {init to not found and busy}

  dev_p := devs.list_p;                {init to first list entry}
  while dev_p <> nil do begin          {scan thru all the list entries}
    if
        (name.len > 0) and then        {caller specified a particular name ?}
        not string_equal (dev_p^.name, name) {but doesn't match this name ?}
      then goto next_dev;              {ignore this device, on to next}
    usbcan_sys_open (dev_p^, hout, hin, stat); {try to open this device}
    if not sys_error(stat) then goto opened; {opened successfully ?}
    busy := true;                      {found suitable device but was not available}
next_dev:                              {advance to next device in list}
    dev_p := dev_p^.next_p;
    end;                               {back to try this new device}
{
*   Unable to open a device.
}
  if name.len > 0
    then begin                         {specific device name was specified}
      if busy
        then begin                     {device was found, but was busy}
          sys_stat_set (usbcan_subsys_k, usbcan_stat_namdevb_k, stat);
          end
        else begin                     {no device of that name was found}
          sys_stat_set (usbcan_subsys_k, usbcan_stat_namdevnf_k, stat);
          end
        ;
      sys_stat_parm_vstr (name, stat);
      end
    else begin                         {no device name was specified}
      if busy
        then begin                     {found device(s), but all busy}
          sys_stat_set (usbcan_subsys_k, usbcan_stat_devbusy_k, stat);
          end
        else begin                     {no device was found}
          sys_stat_set (usbcan_subsys_k, usbcan_stat_nodev_k, stat);
          end
        ;
      end
    ;

  usbcan_devs_dealloc (devs);          {deallocate devices list}
  return;
{
*   Device was successfully opened.  DEV_P is pointing to the info about the
*   device that was opened.
}
opened:
  conn.rw_mode := [file_rw_read_k, file_rw_write_k]; {open for read and write}
  conn.obty := file_obty_dev_k;        {I/O object is a special device}
  conn.fmt := file_fmt_bin_k;          {data format is binary}
  string_copy (dev_p^.path, conn.tnam); {save full system pathname of this device}
  string_copy (conn.tnam, conn.fnam);  {file name same as full pathname}
  string_generic_fnam (conn.tnam, ''(0), conn.gnam); {make generic name}
  conn.ext_num := 0;                   {no file suffix used}
  conn.lnum := 0;                      {init line number, not used}
  sys_mem_alloc (sizeof(dat_p^), dat_p); {allocate memory for our private data}
  conn.data_p := dat_p;                {set pointer to our private connection data}
  conn.close_p := addr(usbcan_sys_close); {install our private close routine}
  conn.sys := 0;                       {not used}

  dat_p^.hout := hout;                 {save handle to output pipe}
  dat_p^.hin := hin;                   {save handle to input pipe}
  dat_p^.name.max := size_char(dat_p^.name.str);
  string_copy (dev_p^.name, dat_p^.name); {save user name of device actually opened}
  usbcan_devs_dealloc (devs);          {deallocate devices list}

  dat_p^.ovl_out.event_h := CreateEventA ( {create event for output overlapped I/O}
    nil,                               {no security attributes supplied}
    win_bool_true_k,                   {no automatic event reset on successful wait}
    win_bool_false_k,                  {init event to not triggered}
    nil);                              {no name supplied}
  if dat_p^.ovl_out.event_h = handle_none_k then begin {error creating event ?}
    stat.sys := GetLastError;
    goto abort1;                       {abort with I/O handles open}
    end;
  dat_p^.ovl_out.offset := 0;
  dat_p^.ovl_out.offset_high := 0;

  dat_p^.ovl_in.event_h := CreateEventA ( {create event for input overlapped I/O}
    nil,                               {no security attributes supplied}
    win_bool_true_k,                   {no automatic event reset on successful wait}
    win_bool_false_k,                  {init event to not triggered}
    nil);                              {no name supplied}
  if dat_p^.ovl_in.event_h = handle_none_k then begin {error creating event ?}
    stat.sys := GetLastError;
    goto abort2;                       {abort, I/O handles and out overlay event open}
    end;
  dat_p^.ovl_in.offset := 0;
  dat_p^.ovl_in.offset_high := 0;

  return;                              {normal return point}
{
*   Error returns.  STAT must already be set to indicate the error.
*
*   Device is open, private data allocated, output overlap event created.
}
abort2:
  discard( CloseHandle (dat_p^.ovl_out.event_h) ); {delete output overlapped event}
{
*   Device is open, private data allocated.
}
abort1:
  discard( CloseHandle (hout) );       {try to close output handle}
  if hin <> hout then begin            {different handle for input ?}
    discard( CloseHandle (hin) );      {try to close input handle}
    end;

  sys_mem_dealloc (dat_p);             {deallocate our private connection data}
  return;                              {return with error}
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_SYS_READ (CONN, ILEN, BUF, OLEN, STAT)
*
*   Read the next chunk of data from the USBCAN device open on CONN.  ILEN is the
*   maximum number of bytes to read into BUF.  OLEN is returned the number of
*   bytes actually read, which will always be from 1 to 64 on no error.  This
*   routine blocks indefinitely until at least one byte is available.
}
procedure usbcan_sys_read (            {read next chunk of bytes from device}
  in out  conn: file_conn_t;           {connection to the device}
  in      ilen: sys_int_adr_t;         {max number of machine adr increments to read}
  out     buf: univ char;              {returned data}
  out     olen: sys_int_adr_t;         {number of machine adresses actually read}
  out     stat: sys_err_t);            {completion status code}
  val_param;

var
  dat_p: conn_data_p_t;                {pointer to our private connection data}
  succ: win_bool_t;                    {system call succeeded}
  ol: win_dword_t;                     {amount of data returned by ReadFile}

label
  retry;

begin
  sys_error_none (stat);               {init to no error}
  dat_p := conn.data_p;                {get pointer to our private data}

retry:                                 {back here if not read any bytes}
  succ := ReadFile (                   {read another chunk from the device}
    dat_p^.hin,                        {handle to input pipe}
    buf,                               {buffer to return the data in}
    min(ilen, 64),                     {max bytes to read, never more then 64}
    ol,                                {returned number of bytes actually read}
    addr(dat_p^.ovl_in));              {pointer to overlapped I/O descriptor}
  if succ = win_bool_false_k then begin {hard error ?}
    if GetLastError <> err_io_pending_k then begin {hard error ?}
      stat.sys := GetLastError;
      return;
      end;
    succ := GetOverlappedResult (      {wait for I/O to complete}
      dat_p^.hin,                      {handle that I/O is pending on}
      dat_p^.ovl_in,                   {overlapped I/O descriptor}
      ol,                              {returned number of bytes actually read}
      win_bool_true_k);                {wait for I/O completion}
    if succ = win_bool_false_k then begin
      stat.sys := GetLastError;
      return;
      end;
    end;
  if ol = 0 then goto retry;           {didn't ready anything, back and try again ?}

  olen := ol;                          {pass back number of bytes actually read}
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_SYS_WRITE (CONN, BUF, LEN, STAT)
*
*   Write the first LEN bytes of BUF to the USBCAN device open on CONN.
}
procedure usbcan_sys_write (           {send data to a device}
  in out  conn: file_conn_t;           {connection to the device}
  in      buf: univ char;              {data to write}
  in      len: sys_int_adr_t;          {number of machine adr increments to write}
  out     stat: sys_err_t);            {completion status code}
  val_param;

var
  dat_p: conn_data_p_t;                {pointer to our private connection data}
  succ: win_bool_t;                    {system call succeeded}
  olen: win_dword_t;                   {number of bytes actually written}

begin
  sys_error_none (stat);               {init to no error}
  dat_p := conn.data_p;                {get pointer to our private data}

  succ := WriteFile (                  {write the data}
    dat_p^.hout,                       {handle to I/O connection}
    buf,                               {the data to write}
    len,                               {number of bytes to write}
    olen,                              {returned number of bytes actually written}
    addr(dat_p^.ovl_out));             {pointer to overlapped I/O structure}
  if succ = win_bool_false_k then begin {hard error ?}
    if GetLastError <> err_io_pending_k then begin {hard error ?}
      stat.sys := GetLastError;
      return;
      end;
    succ := GetOverlappedResult (      {wait for I/O to complete}
      dat_p^.hout,                     {handle that I/O is pending on}
      dat_p^.ovl_out,                  {overlapped I/O descriptor}
      olen,                            {returned number of bytes actually written}
      win_bool_true_k);                {wait for I/O completion}
    if succ = win_bool_false_k then begin
      stat.sys := GetLastError;
      return;
      end;
    end;

  if olen <> len then begin            {didn't write the right amount of data}
    sys_stat_set (file_subsys_k, file_stat_write_size_k, stat);
    sys_stat_parm_vstr (conn.tnam, stat);
    sys_stat_parm_int (len, stat);
    sys_stat_parm_int (olen, stat);
    return;
    end;
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_SYS_CLOSE (CONN_P)
*
*   Private close routine for a I/O connection to a USBCAN device.  A pointer to
*   this routine is installed in the I/O connection descriptor when it is
*   opened, and this routine is called automatically when the connection is
*   closed by FILE_CLOSE.
}
procedure usbcan_sys_close (           {private close routine for device connection}
  in      conn_p: file_conn_p_t);      {pointer to connection to close}
  val_param;

var
  dat_p: conn_data_p_t;                {pointer to our private connection data}
  succ: win_bool_t;                    {system call succeeded}
  stat: sys_err_t;

begin
  sys_error_none (stat);
  dat_p := conn_p^.data_p;             {get pointer to our private data}

  if dat_p^.hout = dat_p^.hin then begin {using a single handle for input and output ?}
    succ := CloseHandle (dat_p^.hout); {close the handle}
    if succ = win_bool_false_k then begin
      stat.sys := GetLastError;
      sys_error_print (stat, '', '', nil, 0);
      sys_bomb;
      end;
    return;
    end;

  succ := CloseHandle (dat_p^.hout);   {close connection to output pipe}
  if succ = win_bool_false_k then begin
    stat.sys := GetLastError;
    sys_error_print (stat, '', '', nil, 0);
    sys_bomb;
    end;

  succ := CloseHandle (dat_p^.hin);    {close connection to input pipe}
  if succ = win_bool_false_k then begin
    stat.sys := GetLastError;
    sys_error_print (stat, '', '', nil, 0);
    sys_bomb;
    end;

  discard( SetEvent (dat_p^.ovl_out.event_h) ); {release threads waiting on I/O completion}
  discard( SetEvent (dat_p^.ovl_in.event_h) );
  Sleep (0);                           {give waiting threads a chance to see closed}
  discard( CloseHandle (dat_p^.ovl_out.event_h) ); {try to close output overlapped event}
  discard( CloseHandle (dat_p^.ovl_in.event_h) ); {try to close input overlapped event}
  end;
