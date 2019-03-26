{   Input reading thread.
}
module usbcan_in;
define usbcan_stat_check;
define usbcan_thread_in;
%include 'usbcan2.ins.pas';
{
********************************************************************************
*
*   Subroutine USBCAN_STAT_CHECK (UC, STAT)
*
*   Abort the thread if STAT indicates failure.  The error status is set
*   appropriately before the thread is exited.  This routine should only be
*   called from a thread private to the library.  User threads should return
*   the completion status directly to the caller.  This routine is for private
*   threads that have no caller to return a status back to.
}
procedure usbcan_stat_check (          {abort thread on error}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      stat: sys_err_t);            {status to check}
  val_param;

begin
  if uc.quit then begin                {trying to close down ?}
    sys_thread_exit;
    end;

  if not sys_error(stat) then return;  {no error, nothing to do ?}
  if not uc.err then begin             {this is first error encountered ?}
    uc.err := true;                    {indicate error in private thread}
    uc.istat := stat;                  {save the offending error status}
    end;

  sys_thread_exit;                     {exit this thread}
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_THREAD_IN (ARG)
*
*   Root routine for the input reading thread.  All data from the device is
*   received by this thread.  Received USB frames are added to the end of the
*   USB frames queue.  Other responses from the device are handled locally.
}
procedure usbcan_thread_in (           {root routine of input reading thread}
  in      arg: sys_int_adr_t);         {address of library state}
  val_param;

const
  flag_fwver_k = 1;                    {FLAGS value for received firmware version}
  flag_name_k = 2;                     {FLAGS value for received name}
  flags_startup_k = 3;                 {FLAGS value for all startup info received}

var
  uc_p: usbcan_p_t;                    {pointer to library state for this use}
  ibuf: array [0 .. 63] of char;       {raw input buffer}
  ibufi: sys_int_machine_t;            {index of next byte to read from IBUF}
  ibufn: sys_int_adr_t;                {number of bytes left to read from IBUF}
  ii: sys_int_machine_t;               {sratch integer and loop counter}
  flags: sys_int_machine_t;            {flags indicating received information}
  ready: boolean;                      {READY already signalled}
  b: sys_int_machine_t;                {scratch data byte value}
  i1: sys_int_machine_t;               {integer response parameters}
  tk: string_var256_t;                 {scratch token}
  fent_p: can_listent_p_t;             {points to next received CAN frame to fill in}
  stat: sys_err_t;                     {completion status}

label
  next_rsp;
{
****************************************
*
*   Internal function IBYTE
*
*   Return the next byte from the input stream.
}
function ibyte                         {return next byte from remote system}
  :sys_int_machine_t;                  {0-255 byte value}

var
  b: sys_int_machine_t;                {the returned byte value}
  stat: sys_err_t;                     {completion status}

label
  retry;

begin
  if uc_p^.quit then begin             {trying to exit the program ?}
    sys_thread_exit;
    end;

retry:                                 {back here after reading new chunk into buffer}
  if ibufn > 0 then begin              {byte is available in local buffer ?}
    b := ord(ibuf[ibufi]);             {get the data byte to return}
    ibufi := ibufi + 1;                {advance buffer index for next time}
    ibufn := ibufn - 1;                {count one less byte left in the buffer}
    ibyte := b;                        {return the data byte}
    return;
    end;

  usbcan_sys_read (                    {read next chunk of data from remote device}
    uc_p^.conn,                        {connection to the device}
    sizeof(ibuf),                      {max amount of data allowed to read}
    ibuf,                              {input buffer to return data in}
    ibufn,                             {number of bytes actually read}
    stat);
  usbcan_stat_check (uc_p^, stat);
  ibufi := 0;                          {reset to fetch from start of buffer}
  goto retry;                          {back to return byte from new chunk}
  end;
{
****************************************
*
*   Function I16
*
*   Read the next 2 input bytes and return their 16 bit integer value.
}
function i16                           {get 16 bit integer}
  :sys_int_machine_t;
  val_param; internal;

var
  i: sys_int_machine_t;

begin
  i := ibyte;
  i := i ! lshft(ibyte, 8);
  i16 := i;
  end;
{
****************************************
*
*   Function I32
*
*   Read the next 4 input bytes and return their 32 bit integer value.
}
function i32                           {get 32 bit integer}
  :sys_int_conv32_t;
  val_param; internal;

var
  i: sys_int_conv32_t;

begin
  i := ibyte;
  i := i ! lshft(ibyte, 8);
  i := i ! lshft(ibyte, 16);
  i := i ! lshft(ibyte, 24);
  i32 := i;
  end;
{
****************************************
*
*   Executable code for subroutine THREAD_IN.
}
begin
  uc_p := univ_ptr(arg);               {get pointer to the library use state}
  ibufn := 0;                          {init the input buffer to empty}
  flags := 0;                          {init to no information received yet}
  ready := false;                      {init to not signalled ready yet}
  tk.max := size_char(tk.str);         {init local var string}
  fent_p := nil;                       {init to no CAN frames queue entry to write into}
{
*   Send initial commands.
}
  usbcan_out_lock (uc_p^);             {get exclusive lock on output}

  for ii := 1 to 16 do begin           {send NOPs to end any partial command}
    usbcan_out_opc (uc_p^, usbcan_cmd_nop_k, stat);
    usbcan_stat_check (uc_p^, stat);
    end;
  usbcan_out_opc (uc_p^, usbcan_cmd_fwver_k, stat); {request firmware version}
  usbcan_stat_check (uc_p^, stat);
  usbcan_out_opc (uc_p^, usbcan_cmd_nameget_k, stat); {request unit name}
  usbcan_stat_check (uc_p^, stat);
  usbcan_out_flush (uc_p^, stat);      {send any buffered data}
  usbcan_stat_check (uc_p^, stat);

  usbcan_out_unlock (uc_p^);           {release lock on the output}
{
*   Process responses from the device in a infinite loop.  The thread is
*   automatically closed when the connection to the device is closed or the QUIT
*   flag is found set.
}
next_rsp:                              {back here to read each new response}
  if fent_p = nil then begin           {no can frames queue entry available ?}
    can_queue_ent_new (uc_p^.inq, fent_p); {get a new unlinked queue entry}
    end;
  b := ibyte;                          {get response opcode}
  case b of                            {which response is it ?}
{
*   NOP
}
0: begin
  end;
{
*   FWVER version
}
1: begin
  uc_p^.fw.typ := ibyte;               {get firmware type ID}
  uc_p^.fw.ver := ibyte;               {get firmware version}
  uc_p^.fw.seq := ibyte;               {get firmware sequence number}

  flags := flags ! flag_fwver_k;       {indicate received firmare version}
  end;
{
*   NAME len string
}
2: begin
  tk.len := 0;                         {init name string to empty}
  i1 := ibyte;                         {get number of characters in the name string}
  for ii := 1 to i1 do begin           {once for each name character}
    string_append1 (tk, chr(ibyte));
    end;

  string_copy (tk, uc_p^.name);        {save the device name}
  flags := flags ! flag_name_k;        {indicate received device name}
  end;
{
*   CSPI_GET byte
}
3: begin
  discard( ibyte );
  end;
{
*   CANFR flags id dat ... dat
*
*   Reports one received CAN frame.
}
4: begin
  i1 := ibyte;                         {get flags byte}
  fent_p^.frame.ndat := min(8, i1 & 15); {get number of data bytes}
  fent_p^.frame.flags := [];
  if (i1 & 2#00010000) <> 0 then begin {extended frame ?}
    fent_p^.frame.flags := fent_p^.frame.flags + [can_frflag_ext_k];
    end;
  if (i1 & 2#00100000) <> 0 then begin {remote request frame ?}
    fent_p^.frame.flags := fent_p^.frame.flags + [can_frflag_rtr_k];
    end;
  if can_frflag_ext_k in fent_p^.frame.flags
    then begin                         {extended frame}
      fent_p^.frame.id := i32;         {get 29 bit ID}
      end
    else begin                         {standard frame}
      fent_p^.frame.id := i16;         {get 11 bit ID}
      end
    ;
  for ii := 0 to fent_p^.frame.ndat-1 do begin {get the data bytes}
    fent_p^.frame.dat[ii] := ibyte;
    end;

  can_queue_ent_put (uc_p^.inq, fent_p); {add this new frame to end of input queue}
  end;
{
*   Unrecognized response opcode.
}
otherwise
    sys_stat_set (usbcan_subsys_k, usbcan_stat_rspbad_k, stat);
    sys_stat_parm_int (b, stat);       {pass the offending response opcode value}
    usbcan_stat_check (uc_p^, stat);
    end;

  if not ready and ((flags & flags_startup_k) = flags_startup_k) then begin
    sys_event_notify_bool (uc_p^.ready); {indicate ready for normal operation}
    ready := true;                     {remember that ready was already signalled}
    end;
  goto next_rsp;                       {done with this response, back for next}
  end;
