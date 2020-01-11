{   Program TEST_USBCAN
*
*   Program to test low level communication with a Embed Inc USB CAN controller.
}
program test_usbcan;
%include 'usbcan2.ins.pas';

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

type
  canfr_t = record                     {one CAN frame}
    id: sys_int_conv32_t;              {frame ID}
    ext: boolean;                      {extended frame, not standard frame}
    rtr: boolean;                      {remote transmit request, not data frame}
    ndat: sys_int_conv8_t;             {number of data bytes, 0-8}
    dat: array[0..7] of int8u_t;       {the data bytes}
    end;

var
  name:                                {name of device to open, empty = first available}
    %include '(cog)lib/string80.ins.pas';
  conn: file_conn_t;                   {connection to the remote unit}
  wrlock: sys_sys_threadlock_t;        {lock for writing to standard output}
  thid_in: sys_sys_thread_id_t;        {ID of read input thread}
  prompt:                              {prompt string for entering command}
    %include '(cog)lib/string4.ins.pas';
  buf:                                 {one line command buffer}
    %include '(cog)lib/string8192.ins.pas';
  obuf:                                {output bytes data buffer}
    %include '(cog)lib/string8192.ins.pas';
  p: string_index_t;                   {BUF parse index}
  quit: boolean;                       {TRUE when trying to exit the program}
  newline: boolean;                    {STDOUT stream is at start of new line}
  i1, i2, i3: sys_int_machine_t;       {integer command parameters}
  showin: boolean;                     {show each individual input byte}
  showout: boolean;                    {show each individual output byte}
  cmds:                                {command names separated by space}
    %include '(cog)lib/string8192.ins.pas';
  canfr: canfr_t;                      {one CAN frame}
  dat: array[0 .. 255] of int8u_t;     {scratch array of data bytes}

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, err_parm, parm_bad, done_opts,
  loop_cmd, loop_hex, get_can_data, tkline, loop_tk,
  done_cmd, err_extra, err_cmparm, leave;
{
********************************************************************************
*
*   Subroutine ADDCMD (NAME)
*
*   Add the command NAME to the commands list.
}
procedure addcmd (                     {add command to commands list}
  in      name: string);               {name of command to add, blank pad or NULL term}
  val_param; internal;

var
  n: string_var32_t;                   {upper case var string copy of command name}

begin
  n.max := size_char(n.str);           {init local var string}

  string_vstring (n, name, size_char(name)); {make var string command name}
  string_upcase (n);                   {upper case for keyword mathing later}
  string_append_token (cmds, n);       {append to end of commands list}
  end;
{
********************************************************************************
*
*   Subroutine LOCKOUT
*
*   Acquire exclusive lock for writing to standard output.
}
procedure lockout;

begin
  sys_thread_lock_enter (wrlock);
  if not newline then writeln;         {start on a new line}
  newline := true;                     {init to STDOUT will be at start of line}
  end;
{
********************************************************************************
*
*   Subroutine UNLOCKOUT
*
*   Release exclusive lock for writing to standard output.
}
procedure unlockout;

begin
  sys_thread_lock_leave (wrlock);
  end;
{
********************************************************************************
*
*   Subroutine WHEX (B)
*
*   Write the byte value in the low 8 bits of B as two hexadecimal digits
*   to standard output.
}
procedure whex (                       {write hex byte to standard output}
  in      b: sys_int_machine_t);       {byte value in low 8 bits}
  val_param; internal;

var
  tk: string_var16_t;                  {hex string}
  stat: sys_err_t;

begin
  tk.max := size_char(tk.str);         {init local var string}

  string_f_int_max_base (              {make the hex string}
    tk,                                {output string}
    b & 255,                           {input integer}
    16,                                {radix}
    2,                                 {field width}
    [ string_fi_leadz_k,               {pad field on left with leading zeros}
      string_fi_unsig_k],              {the input integer is unsigned}
    stat);
  write (tk.str:tk.len);               {write the string to standard output}
  end;
{
********************************************************************************
*
*   Subroutine WDEC (B)
*
*   Write the byte value in the low 8 bits of B as an unsigned decimal
*   integer to standard output.  Exactly 3 characters are written with
*   leading zeros as blanks.
}
procedure wdec (                       {write byte to standard output in decimal}
  in      b: sys_int_machine_t);       {byte value in low 8 bits}
  val_param; internal;

var
  tk: string_var16_t;                  {hex string}
  stat: sys_err_t;

begin
  tk.max := size_char(tk.str);         {init local var string}

  string_f_int_max_base (              {make the hex string}
    tk,                                {output string}
    b & 255,                           {input integer}
    10,                                {radix}
    3,                                 {field width}
    [string_fi_unsig_k],               {the input integer is unsigned}
    stat);
  write (tk.str:tk.len);               {write the string to standard output}
  end;
{
********************************************************************************
*
*   Subroutine WFP (R, N)
*
*   Write the floating point value R in free format with N digits right of the
*   decimal point.
}
(*
procedure wfp (                        {write floating point free format value}
  in      r: real;                     {floating point value to write}
  in      n: sys_int_machine_t);       {digits right of decimal point}
  val_param; internal;

var
  tk: string_var16_t;                  {hex string}

begin
  tk.max := size_char(tk.str);         {init local var string}

  string_f_fp_fixed (tk, r, n);
  write (tk.str:tk.len);
  end;
*)
{
********************************************************************************
*
*   Subroutine WPRT (B)
*
*   Show the byte value in the low 8 bits of B as a character, if it is
*   a valid character code.  If not, write a description of the code.
}
procedure wprt (                       {show printable character to standard output}
  in      b: sys_int_machine_t);       {byte value in low 8 bits}
  val_param; internal;

var
  c: sys_int_machine_t;                {character code}

begin
  c := b & 255;                        {extract the character code}

  case c of                            {check for a few special handling cases}
0: write ('NULL');
7: write ('^G bell');
10: write ('^J LF');
13: write ('^M CR');
17: write ('^Q Xon');
19: write ('^S Xoff');
27: write ('Esc');
32: write ('SP');
127: write ('DEL');
otherwise
    if c >= 33 then begin              {printable character ?}
      write (chr(c));                  {let system display the character directly}
      return;
      end;
    if (c >= 1) and (c <= 26) then begin {CTRL-letter ?}
      write ('^', chr(c+64));
      return;
      end;
    end;                               {end of special handling cases}
  end;
{
********************************************************************************
*
*   Subroutine WCANFR (CANFR)
*
*   Write the contents of the CAN frame in CANFR to standard output.  The output
*   lock should be held by the caller.
}
procedure wcanfr (                     {write CAN frame to standard output}
  in      canfr: canfr_t);             {the CAN frame to show}
  val_param; internal;

var
  i: sys_int_machine_t;                {loop counter}
  tk: string_var32_t;                  {scratch token}
  stat: sys_err_t;

begin
  tk.max := size_char(tk.str);         {init local var string}

  write ('CAN frame ');

  if canfr.ext
    then begin                         {extended frame}
      string_f_int32h (tk, canfr.id);
      end
    else begin                         {standard frame}
      write ('     ');
      string_f_int_max_base (          {make 3 digit HEX string from frame ID}
        tk,                            {output string}
        canfr.id,                      {input integer}
        16,                            {radix}
        3,                             {fixed field width}
        [ string_fi_leadz_k,           {pad with leading zeros to fill field}
          string_fi_unsig_k],          {input number is unsigned}
        stat);
      sys_error_abort (stat, '', '', nil, 0);
      end
    ;
  write (tk.str:tk.len, 'h');
  string_f_int_max_base (              {make 4 digit decimal frame ID string}
    tk,                                {output string}
    canfr.id,                          {input integer}
    10,                                {radix}
    10,                                {fixed field width}
    [string_fi_unsig_k],               {input number is unsigned}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  write (tk.str:tk.len);

  if canfr.rtr then begin              {remote transmit request ?}
    writeln (' RTR');
    return;                            {RTR frames never have data bytes}
    end;

  if canfr.ndat = 0
    then begin                         {no data bytes}
      writeln (', ', canfr.ndat, ' data bytes');
      end
    else begin                         {at least one data byte}
      write (', ', canfr.ndat, ' data byte');
      if canfr.ndat > 1 then begin
        write ('s');
        end;
      writeln (':');

      write ('  hex:');                {write data bytes in HEX}
      for i := 1 to canfr.ndat do begin
        write ('  ');
        whex (canfr.dat[i-1]);
        end;
      writeln;

      write ('  dec:');                {write data bytes in decimal}
      for i := 1 to canfr.ndat do begin
        write (' ');
        wdec (canfr.dat[i-1]);
        end;
      writeln;
      end
    ;
  end;
{
********************************************************************************
*
*   Subroutine THREAD_IN (ARG)
*
*   This routine is run in a separate thread.  It reads data bytes
*   from the input and writes information about the received
*   data to standard output.
}
procedure thread_in (                  {process input from the remote unit}
  in      arg: sys_int_adr_t);         {unused argument}
  val_param; internal;

var
  ibuf: array [0 .. 63] of char;       {raw input buffer}
  ibufi: sys_int_machine_t;            {index of next byte to read from IBUF}
  ibufn: sys_int_adr_t;                {number of bytes left to read from IBUF}
  b: sys_int_machine_t;                {scratch data byte value}
  i: sys_int_machine_t;                {scratch integer and loop counter}
  i1, i2, i3: sys_int_machine_t;       {integer response parameters}
  tk: string_var80_t;                  {scratch token}
  canfr: canfr_t;                      {one CAN frame}

label
  next_rsp;
{
******************************
*
*   Local function IBYTE
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
  if quit then begin                   {trying to exit the program ?}
    sys_thread_exit;
    end;

retry:                                 {back here after reading new chunk into buffer}
  if ibufn > 0 then begin              {byte is available in local buffer ?}
    b := ord(ibuf[ibufi]);             {get the data byte to return}
    ibufi := ibufi + 1;                {advance buffer index for next time}
    ibufn := ibufn - 1;                {count one less byte left in the buffer}
    if showin then begin               {show each individual input byte ?}
      lockout;                         {acquire exclusive lock on standard output}
      write ('Received byte: ');
      wdec (b);                        {show byte value in decimal}
      write (' ');
      whex (b);                        {show byte value in HEX}
      write ('h ');
      wprt (b);                        {show printable character, if possible}
      writeln;
      unlockout;                       {release lock on standard output}
      end;
    ibyte := b;                        {return the data byte}
    return;
    end;

  usbcan_sys_read (                    {read next chunk of data from remote device}
    conn,                              {connection to the device}
    sizeof(ibuf),                      {max amount of data allowed to read}
    ibuf,                              {input buffer to return data in}
    ibufn,                             {number of bytes actually read}
    stat);
  if quit then begin                   {trying to exit the program ?}
    sys_thread_exit;
    end;
  sys_error_abort (stat, '', '', nil, 0);
  ibufi := 0;                          {reset to fetch from start of buffer}

  goto retry;                          {back to return byte from new chunk}
  end;
{
******************************
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
******************************
*
*   Function I16S
*
*   Read the next 2 input bytes and return their signed 16 bit integer value.
}
(*
function i16s                          {get 16 bit signed integer}
  :sys_int_machine_t;
  val_param; internal;

var
  i: sys_int_machine_t;

begin
  i := i16;                            {get raw 16 bit integer}
  if i > 16#7FFF then i := i - 16#10000;
  i16s := i;
  end;
*)
{
******************************
*
*   Function I24
*
*   Read the next 3 input bytes and return their 24 bit integer value.
}
(*
function i24                           {get 24 bit integer}
  :sys_int_machine_t;
  val_param; internal;

var
  i: sys_int_machine_t;

begin
  i := ibyte;
  i := i ! lshft(ibyte, 8);
  i := i ! lshft(ibyte, 16);
  i24 := i;
  end;
*)
{
******************************
*
*   Function I24S
*
*   Read the next 3 input bytes and return their signed 24 bit integer value.
}
(*
function i24s                          {get 24 bit signed integer}
  :sys_int_machine_t;
  val_param; internal;

var
  i: sys_int_machine_t;

begin
  i := i24;                            {get raw 24 bit integer}
  if i > 16#7FFFFF then i := i - 16#1000000;
  i24s := i;
  end;
*)
{
******************************
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
******************************
*
*   Executable code for subroutine THREAD_IN.
}
begin
  tk.max := size_char(tk.str);         {init local var string}
  ibufn := 0;                          {init input buffer to empty}

next_rsp:                              {back here to read each new response packet}
  b := ibyte;                          {get response opcode byte}
  case b of                            {which response opcode is it ?}
{
*   NOP
}
0: begin
  lockout;
  writeln ('NOP');
  unlockout;
  end;
{
*   FWVER version
}
1: begin
  i1 := ibyte;                         {get firmware type}
  i2 := ibyte;                         {get the firmware version number}
  i3 := ibyte;                         {get sequence number}

  lockout;
  write ('Firmare ');
  case i1 of                           {which firmware type is it ?}
1:  write ('H1CAN');
otherwise
    write ('type ', i1);
    end;
  writeln (' ver ', i2, ' seq ', i3);
  unlockout;
  end;
{
*   NAME len string
}
2: begin
  tk.len := 0;                         {init name string to empty}
  i1 := ibyte;                         {get number of characters in the name string}
  for i := 1 to i1 do begin            {once for each name character}
    string_append1 (tk, chr(ibyte));
    end;
  lockout;
  writeln ('NAME "', tk.str:tk.len, '"');
  unlockout;
  end;
{
*   CSPI_GET byte
}
3: begin
  i1 := ibyte;                         {get the 0-255 data byte value}
  lockout;
  write ('CAN SPI byte ');
  whex (i1);
  write ('h ');
  wdec (i1);
  write (' ');
  wprt (i1);
  writeln;
  unlockout;
  end;
{
*   CANFR flags id dat ... dat
*
*   Reports one received CAN frame.
}
4: begin
  i1 := ibyte;                         {get flags byte}
  canfr.ndat := min(i1 & 15, 8);       {extract number data bytes}
  canfr.ext := (i1 & 2#00010000) <> 0; {interpret extended frame flag}
  canfr.rtr := (i1 & 2#00100000) <> 0; {interpret remote transmit request flag}
  if canfr.ext
    then begin                         {extended frame}
      canfr.id := i32;                 {get 29 bit ID}
      end
    else begin                         {standard frame}
      canfr.id := i16;                 {get 11 bit ID}
      end
    ;
  for i := 1 to canfr.ndat do begin    {get the data bytes}
    canfr.dat[i-1] := ibyte;
    end;

  lockout;
  wcanfr (canfr);                      {show the CAN frame contents}
  unlockout;
  end;
{
*   Unrecognized response opcode.
}
otherwise
    lockout;
    write ('Unrecognized response opcode: ');
    wdec (b);                          {show byte value in decimal}
    write (' ');
    whex (b);                          {show byte value in HEX}
    write ('h ');
    wprt (b);                          {show printable character, if possible}
    writeln;
    unlockout;
    end;

  goto next_rsp;                       {done with this response, back for next}
  end;
{
********************************************************************************
*
*   Subroutine NEXT_TOKEN (TK, STAT)
*
*   Get the next token from BUF into TK.
}
procedure next_token (                 {get next token from BUF}
  in out  tk: univ string_var_arg_t;   {returned token}
  out     stat: sys_err_t);
  val_param;

begin
  string_token (buf, p, tk, stat);
  end;
{
********************************************************************************
*
*   Subroutine NEXT_KEYW (TK, STAT)
*
*   Parse the next token from BUF as a keyword and return it in TK.
}
procedure next_keyw (
  in out  tk: univ string_var_arg_t;   {returned token}
  out     stat: sys_err_t);
  val_param;

begin
  string_token (buf, p, tk, stat);
  string_upcase (tk);
  end;
{
********************************************************************************
*
*   Function NEXT_ONOFF (STAT)
*
*   Parse the next token from BUF and interpret as "ON" or "OFF".  The
*   function value will be TRUE for ON, and FALSE for off.
}
function next_onoff (                  {get next token as integer value}
  out     stat: sys_err_t)             {completion status code}
  :boolean;
  val_param;

var
  tk: string_var16_t;                  {next keyword from BUF}
  t: boolean;                          {interpreted true/false response}

begin
  tk.max := size_char(tk.str);         {init local var string}
  next_onoff := false;                 {init return value to stop C compiler warning}

  next_keyw (tk, stat);                {get next keyword in TK}
  if sys_error(stat) then return;

  string_t_bool (tk, [string_tftype_onoff_k], t, stat); {interpret response into T}
  next_onoff := t;
  end;
{
********************************************************************************
*
*   Function NEXT_INT (MN, MX, STAT)
*
*   Parse the next token from BUF and return its value as an integer.
*   MN and MX are the min/max valid range of the integer value.
}
function next_int (                    {get next token as integer value}
  in      mn, mx: sys_int_machine_t;   {valid min/max range}
  out     stat: sys_err_t)             {completion status code}
  :sys_int_machine_t;
  val_param;

var
  i: sys_int_machine_t;

begin
  string_token_int (buf, p, i, stat);  {get token value in I}
  next_int := i;                       {pass back value}
  if sys_error(stat) then return;

  if (i < mn) or (i > mx) then begin   {out of range}
    lockout;
    writeln ('Value ', i, ' is out of range.');
    unlockout;
    sys_stat_set (sys_subsys_k, sys_stat_failed_k, stat);
    end;
  end;
{
********************************************************************************
*
*   Function NEXT_INT_HEX (MN, MX, STAT)
*
*   Parse the next token from BUF, interpret it as a HEX integer, and return
*   the result.  MN and MX are the min/max valid range of the integer value.
}
(*
function next_int_hex (                {get next token as HEX integer}
  in      mn, mx: int32u_t;            {valid min/max range}
  out     stat: sys_err_t)             {completion status code}
  :int32u_t;
  val_param;

var
  j: sys_int_max_t;                    {integer value of token}
  i: int32u_t;
  tk: string_var32_t;                  {scratch token}

begin
  tk.max := size_char(tk.str);         {init local var string}
  next_int_hex := 0;                   {disable annoying compiler warning}

  string_token (buf, p, tk, stat);     {get the HEX integer string into TK}
  if sys_error(stat) then return;

  string_t_int_max_base (              {convert the string to integer}
    tk,                                {input string}
    16,                                {radix}
    [string_ti_unsig_k],               {HEX value is unsigned}
    j,                                 {output integer}
    stat);
  if sys_error(stat) then return;
  i := j;

  next_int_hex := i;                   {pass back value}
  if sys_error(stat) then return;

  if (i < mn) or (i > mx) then begin   {out of range}
    lockout;
    writeln ('Value ', i, ' is out of range.');
    unlockout;
    sys_stat_set (sys_subsys_k, sys_stat_failed_k, stat);
    end;
  end;
*)
{
********************************************************************************
*
*   Function NEXT_IPADR (STAT)
*
*   Parse the next token as a IP address in dot notation or a machine name
*   and return the resulting 32 bit IP address.
}
(*
function next_ipadr (                  {get next token as IP address}
  out     stat: sys_err_t)             {completion status code}
  :sys_inet_adr_node_t;
  val_param;

var
  tk: string_var256_t;                 {scratch token}
  ipadr: sys_inet_adr_node_t;

begin
  tk.max := size_char(tk.str);         {init local var string}
  next_ipadr := 0;                     {keep compiler from complaining}

  next_token (tk, stat);               {get machine name or dot notation address}
  if sys_error(stat) then return;
  file_inet_name_adr (tk, ipadr, stat); {convert to binary IP address}
  next_ipadr := ipadr;                 {return the result}
  end;
*)
{
********************************************************************************
*
*   Function NEXT_FP (STAT)
*
*   Parse the next token from BUF and return its value as a floating
*   point number.
}
(*
function next_fp (                     {get next token as floating point value}
  out     stat: sys_err_t)             {completion status code}
  :real;
  val_param;

var
  r: real;

begin
  string_token_fpm (buf, p, r, stat);
  next_fp := r;
  end;
*)
{
********************************************************************************
*
*   Function NOT_EOS
*
*   Returns TRUE if the input buffer BUF was is not exhausted.  This is
*   used to check for additional tokens at the end of a command.
}
function not_eos                       {check for more tokens left}
  :boolean;                            {TRUE if more tokens left in BUF}

var
  psave: string_index_t;               {saved copy of BUF parse index}
  tk: string_var4_t;                   {token parsed from BUF}
  stat: sys_err_t;                     {completion status code}

begin
  tk.max := size_char(tk.str);         {init local var string}

  not_eos := false;                    {init to BUF has been exhausted}
  psave := p;                          {save current BUF parse index}
  string_token (buf, p, tk, stat);     {try to get another token}
  if sys_error(stat) then return;      {assume normal end of line encountered ?}
  not_eos := true;                     {indicate a token was found}
  p := psave;                          {reset parse index to get this token again}
  end;
{
********************************************************************************
*
*   Subroutine SEND8 (I)
*
*   Send the low 8 bits of I.
}
procedure send8 (                      {send 8 bits to remote unit}
  in      i: sys_int_machine_t);       {data to send in low bits}
  val_param; internal;

begin
  if showout then begin
    lockout;
    write ('      Sending: ');
    wdec (i);
    write (' ');
    whex (i);
    write ('h ');
    wprt (i);
    writeln;
    unlockout;
    end;

  string_append1 (obuf, chr(i & 255));
  end;
{
********************************************************************************
*
*   Subroutine SEND16 (I)
*
*   Send the low 16 bits of I.
}
procedure send16 (                     {send 16 bits to remote unit}
  in      i: sys_int_machine_t);       {data to send in low bits}
  val_param; internal;

begin
  send8 (i);
  send8 (rshft(i, 8));
  end;
{
********************************************************************************
*
*   Subroutine SEND24 (I)
*
*   Send the low 24 bits of I.
}
(*
procedure send24 (                     {send 24 bits to remote unit}
  in      i: sys_int_machine_t);       {data to send in low bits}
  val_param; internal;

begin
  send8 (i);
  send8 (rshft(i, 8));
  send8 (rshft(i, 16));
  end;
*)
{
********************************************************************************
*
*   Subroutine SEND32 (I)
*
*   Send the low 32 bits of I.
}
procedure send32 (                     {send 32 bits to remote unit}
  in      i: sys_int_conv32_t);        {data to send in low bits}
  val_param; internal;

begin
  send8 (i);
  send8 (rshft(i, 8));
  send8 (rshft(i, 16));
  send8 (rshft(i, 24));
  end;
{
********************************************************************************
*
*   SEND_CAN (CANFR)
*
*   Send the CAN frame in CANFR to the remote unit and cause it to be sent over
*   the CAN bus.
}
procedure send_can (                   {send CAN frame}
  in      canfr: canfr_t);             {the CAN frame to send}
  val_param; internal;

var
  ii: sys_int_machine_t;

begin
  if canfr.rtr then begin              {this is a remote request frame ?}
    if canfr.ext
      then begin                       {extended remote request frame}
        send8 (12);
        send32 (canfr.id);
        end
      else begin                       {standard remote request frame}
        send8 (11);
        send16 (canfr.id);
        end
      ;
    return;                            {done with remote request frame}
    end;

  if canfr.ext
    then begin                         {extended data frame}
      send8 (10);
      send32 (canfr.id);
      end
    else begin                         {standard data frame}
      send8 (9);
      send16 (canfr.id);
      end
    ;
  send8 (canfr.ndat);                  {send number of data bytes to follow}
  for ii := 1 to canfr.ndat do begin   {send the data bytes}
    send8 (canfr.dat[ii-1]);
    end;
  end;
{
********************************************************************************
*
*   Subroutine SEND
*
*   Send the contents of the output buffer to the device.  Nothing is done
*   if the output buffer is empty.  The output buffer will always be empty
*   when this routine returns.
}
procedure send;
  val_param; internal;

var
  stat: sys_err_t;                     {completion status}

begin
  if obuf.len > 0 then begin           {one or more bytes to send ?}
    usbcan_sys_write (conn, obuf.str, obuf.len, stat); {send the data bytes}
    sys_error_abort (stat, '', '', nil, 0);
    end;
  obuf.len := 0;                       {reset the buffer to empty}
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
{
*   Initialize our state before reading the command line options.
}
  showin := false;
  showout := false;
  string_cmline_init;                  {init for reading the command line}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-N',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -N name
}
1: begin
  string_cmline_token (name, stat);
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {unrecognized command line option}
    end;                               {end of command line option case statement}

err_parm:                              {jump here on error with parameter}
  string_cmline_parm_check (stat, opt); {check for bad command line option parameter}
  goto next_opt;                       {back for next command line option}

parm_bad:                              {jump here on got illegal parameter}
  string_cmline_reuse;                 {re-read last command line token next time}
  string_cmline_token (parm, stat);    {re-read the token for the bad parameter}
  sys_msg_parm_vstr (msg_parm[1], parm);
  sys_msg_parm_vstr (msg_parm[2], opt);
  sys_message_bomb ('string', 'cmline_parm_bad', msg_parm, 2);

done_opts:                             {done with all the command line options}
{
*   All done reading the command line.
}
  usbcan_sys_open_name (name, conn, stat); {open connection to the device}
  sys_error_abort (stat, '', '', nil, 0);
{
*   Perform some system initialization.
}
  sys_thread_lock_create (wrlock, stat); {create interlock for writing to STDOUT}
  sys_error_abort (stat, '', '', nil, 0);

  quit := false;                       {init to not trying to exit the program}
  newline := true;                     {STDOUT is currently at start of new line}

  sys_thread_create (                  {start thread for reading serial line input}
    addr(thread_in),                   {address of thread root routine}
    0,                                 {argument passed to thread (unused)}
    thid_in,                           {returned thread ID}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
{
*   Send initial commands to get basic configuration information.
}
  send8 (1);                           {request firmware version}
  send8 (3);                           {request the device's user-settable name}
{
*   Initialize before command processing.
}
  string_vstring (prompt, ': '(0), -1); {set command prompt string}

  addcmd ('?');                        {1}
  addcmd ('HELP');                     {2}
  addcmd ('Q');                        {3}
  addcmd ('S');                        {4}
  addcmd ('H');                        {5}
  addcmd ('SHIN');                     {6}
  addcmd ('FWVER');                    {7}
  addcmd ('NAME');                     {8}
  addcmd ('LEDS');                     {9}
  addcmd ('CS');                       {10}
  addcmd ('CP');                       {11}
  addcmd ('CG');                       {12}
  addcmd ('CE');                       {13}
  addcmd ('SENDS');                    {14}
  addcmd ('SENDE');                    {15}
  addcmd ('SENDSR');                   {16}
  addcmd ('SENDER');                   {17}
  addcmd ('SHOUT');                    {18}
  addcmd ('RD');                       {19}
  addcmd ('WR');                       {20}
{
***************************************
*
*   Process user commands.
}
loop_cmd:                              {back here each new input line}
  send;                                {make sure any previously pending output bytes are sent}
  sys_wait (0.100);
  lockout;
  string_prompt (prompt);              {prompt the user for a command}
  newline := false;                    {indicate STDOUT not at start of new line}
  unlockout;

  string_readin (buf);                 {get command from the user}
  newline := true;                     {STDOUT now at start of line}
  if buf.len <= 0 then goto loop_cmd;  {ignore blank lines}
  p := 1;                              {init BUF parse index}
  while buf.str[p] = ' ' do begin      {skip over spaces before new token}
    if p >= buf.len then goto loop_cmd; {only blanks found, ignore line ?}
    p := p + 1;                        {skip over this blank}
    end;
  if (buf.str[p] = '''') or (buf.str[p] = '"') {quoted string ?}
    then goto tkline;                  {this line contains data tokens}
  string_token (buf, p, opt, stat);    {get command name token into OPT}
  if string_eos(stat) then goto loop_cmd; {ignore line if no command found}
  if sys_error(stat) then goto err_cmparm;
  string_t_int (opt, i1, stat);        {try to convert command token to integer}
  if not sys_error (stat) then goto tkline; {this line contains only data tokens ?}
  sys_error_none (stat);
  string_upcase (opt);
  string_tkpick (opt, cmds, pick);     {pick command name from list}
  case pick of
{
*   HELP
}
1, 2: begin
  if not_eos then goto err_extra;
  lockout;
  writeln;
  writeln ('? or HELP   - Show this list of commands');
  writeln ('Q           - Quit the program');
  writeln ('S chars     - Remaining characters sent as ASCII');
  writeln ('H hex ... hex - Data bytes, tokens interpreted in hexadecimal');
  writeln ('val ... "chars" - Integer bytes or chars, chars must be quoted, "" or ''''');
  writeln ('  Integer tokens have the format: [base#]value with decimal default');
  writeln ('SHIN on|off - Show all raw input bytes from unit');
  writeln ('SHOUT on|off - Show all raw output bytes to unit');
  writeln ('FWVER       - Request the firmware version');
  writeln ('NAME [name] - Set or show user-settable name');
  writeln ('LEDS val    - Show 0-7 value on the debug LEDS');
  writeln ('CS          - Start SPI sequence to CAN controller');
  writeln ('CP byte     - Send byte over SPI to CAN controller');
  writeln ('CG          - Get byte over SPI from CAN controller');
  writeln ('CE          - End SPI sequence to CAN controller');
  writeln ('RD adr n    - Read bytes from CAN controller');
  writeln ('WR adr dat ... dat - Write bytes to CAN controller');
  writeln ('SENDS id dat ... dat - Send standard CAN data frame');
  writeln ('SENDE id dat ... dat - Send extended CAN data frame');
  writeln ('SENDSR id   - Send standard CAN remote request frame');
  writeln ('SENDER id   - Send extended CAN remote request frame');
  unlockout;
  end;
{
*   Q
}
3: begin
  if not_eos then goto err_extra;
  goto leave;
  end;
{
*   S chars
}
4: begin
  string_substr (buf, p, buf.len, obuf);
  end;
{
*   H hexval ... hexval
}
5: begin
loop_hex:                              {back here each new hex value}
  string_token (buf, p, parm, stat);   {get the next token from the command line}
  if string_eos(stat) then goto done_cmd; {exhausted the command line ?}
  string_t_int32h (parm, i1, stat);    {convert this token to integer}
  if sys_error(stat) then goto err_cmparm;
  i1 := i1 & 255;                      {force into 8 bits}
  string_append1 (obuf, chr(i1));      {one more byte to send due to this command}
  goto loop_hex;                       {back to get next command line token}
  end;
{
*   SHIN on|off
*
*   Enable/disable showing all raw input bytes.
}
6: begin
  showin := next_onoff (stat);
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;
  end;
{
*   FWVER
}
7: begin
  if not_eos then goto err_extra;
  send8 (1);
  end;
{
*   NAME [name]
}
8: begin
  next_token (parm, stat);             {try to get name token}

  if string_eos(stat) then begin       {no command parameter supplied, get name}
    string_append1 (obuf, chr(3));     {NAMEGET command}
    goto done_cmd;
    end;

  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;

  string_append1 (obuf, chr(2));       {NAMESET command}
  string_append1 (obuf, chr(0));       {init to 0 name length for now}
  string_append (obuf, parm);          {add the name string characters}
  obuf.str[2] := chr(obuf.len - 2);    {set final number of name characters}
  end;
{
*   LEDS val
*
*   Set the debug LEDs to the indicated value.
}
9: begin
  i1 := next_int (0, 7, stat);
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;

  send8 (4);                           {SETDBG opcode}
  send8 (i1);                          {value to show on the debug LEDs}
  end;
{
*   CS
*
*   Start SPI sequence to CAN controller.
}
10: begin
  if not_eos then goto err_extra;

  send8 (5);                           {CSPI_START opcode}
  end;
{
*   CP byte
*
*   Send byte over SPI to CAN controller.
}
11: begin
  i1 := next_int (-128, 255, stat);
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;

  send8 (6);                           {CSPI_PUT opcode}
  send8 (i1);                          {the data byte}
  end;
{
*   CG
*
*   Get byte over SPI from CAN controller.
}
12: begin
  if not_eos then goto err_extra;

  send8 (7);                           {CSPI_GET opcode}
  end;
{
*   CE
*
*   End the SPI sequence to the CAN controller.
}
13: begin
  if not_eos then goto err_extra;

  send8 (8);                           {CSPI_END opcode}
  end;
{
*   SENDS id dat ... dat
*
*   Send standard CAN data frame.
}
14: begin
  canfr.ext := false;
  canfr.rtr := false;
  canfr.id := next_int (0, 16#7FF, stat);
  if sys_error(stat) then goto err_cmparm;

get_can_data:                          {common code to read CAN data bytes and send CAN frame}
  canfr.ndat := 0;                     {init number of data bytes}
  while true do begin
    if canfr.ndat >= 8 then begin      {no more data allowed ?}
      if not_eos then goto err_extra;
      end;
    canfr.dat[canfr.ndat] := next_int (-128, 255, stat);
    if string_eos(stat) then exit;
    canfr.ndat := canfr.ndat + 1;
    end;

  send_can (canfr);                    {send the CAN frame}
  end;
{
*   SENDE id dat ... dat
*
*   Send extended CAN data frame.
}
15: begin
  canfr.ext := true;
  canfr.rtr := false;
  canfr.id := next_int (0, 16#1FFFFFFF, stat);
  if sys_error(stat) then goto err_cmparm;
  goto get_can_data;                   {get data bytes and send the CAN frame}
  end;
{
*   SENDSR id
*
*   Send standard CAN remote request frame.
}
16: begin
  canfr.ext := false;
  canfr.rtr := true;
  canfr.id := next_int (0, 16#7FF, stat);
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;
  canfr.ndat := 0;
  send_can (canfr);
  end;
{
*   SENDER id
*
*   Send extended CAN remote request frame.
}
17: begin
  canfr.ext := true;
  canfr.rtr := true;
  canfr.id := next_int (0, 16#1FFFFFFF, stat);
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;
  canfr.ndat := 0;
  send_can (canfr);
  end;
{
*   SHOUT on|off
*
*   Enable/disable showing all raw input bytes.
}
18: begin
  showout := next_onoff (stat);
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;
  end;
{
*   RD adr n
}
19: begin
  i1 := next_int (0, 16#7F, stat);     {get starting address}
  if sys_error(stat) then goto err_cmparm;
  i2 := next_int (0, 128, stat);       {get number of bytes to read}
  if string_eos(stat)
    then begin                         {no length specified}
      i2 := 1;                         {default to 1 byte}
      end
    else begin                         {length specified or error}
      if sys_error(stat) then goto err_cmparm;
      if not_eos then goto err_extra;
      end
    ;

  send8 (5);                           {CSPI_START}
  send8 (6); send8 (3);                {SPI opcode for read}
  send8 (6); send8 (i1);               {start address of the read}
  for i3 := 1 to i2 do begin           {once for each byte to read}
    send8 (7);                         {CSPI_GET}
    end;
  send8 (8);                           {CSPI_END}
  end;
{
*   WR adr dat ... dat
}
20: begin
  i1 := next_int (0, 16#7F, stat);     {get starting address}
  if sys_error(stat) then goto err_cmparm;
  i2 := 0;                             {init number of data bytes}
  while true do begin
    i3 := next_int (-128, 255, stat);
    if string_eos(stat) then exit;
    if sys_error(stat) then goto err_cmparm;
    if i2 <= 255 then begin
      dat[i2] := i3;
      i2 := i2 + 1;
      end;
    end;

  send8 (5);                           {CSPI_START}
  send8 (6); send8 (2);                {SPI opcode for write}
  send8 (6); send8 (i1);               {start address of the write}
  for i3 := 1 to i2 do begin
    send8 (6);                         {CSPI_PUT}
    send8 (dat[i3-1]);                 {data byte to write}
    end;
  send8 (8);                           {CSPI_END}
  end;
{
*   Unrecognized command.
}
otherwise
    lockout;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_parms ('string', 'err_command_bad', msg_parm, 1);
    unlockout;
    goto loop_cmd;
    end;
  goto done_cmd;                       {done handling this command}
{
*   The line contains data tokens.  Process each and add the resulting bytes to OBUF.
}
tkline:
  p := 1;                              {reset to parse position to start of line}

loop_tk:                               {back here to get each new data token}
  if p > buf.len then goto done_cmd;   {exhausted command line ?}
  while buf.str[p] = ' ' do begin      {skip over spaces before new token}
    if p >= buf.len then goto done_cmd; {nothing more left on this command line ?}
    p := p + 1;                        {skip over this blank}
    end;
  if (buf.str[p] = '"') or (buf.str[p] = '''') then begin {token is a quoted string ?}
    string_token (buf, p, parm, stat); {get resulting string into PARM}
    if sys_error(stat) then goto err_cmparm;
    string_append (obuf, parm);        {add string to bytes to send}
    goto loop_tk;                      {back to get next token}
    end;

  string_token (buf, p, parm, stat);   {get this token into PARM}
  if sys_error(stat) then goto err_cmparm;
  string_t_int (parm, i1, stat);       {convert token to integer}
  if sys_error(stat) then goto err_cmparm;
  i1 := i1 & 255;                      {keep only the low 8 bits}
  string_append1 (obuf, chr(i1));
  goto loop_tk;

done_cmd:                              {done processing the current command}
  if sys_error(stat) then goto err_cmparm; {handle error, if any}

  if not_eos then begin                {extraneous token after command ?}
err_extra:
    lockout;
    writeln ('Too many parameters for this command.');
    unlockout;
    end;
  goto loop_cmd;                       {back to process next command input line}

err_cmparm:                            {parameter error, STAT set accordingly}
  lockout;
  sys_error_print (stat, '', '', nil, 0);
  unlockout;
  goto loop_cmd;

leave:
  quit := true;                        {tell all threads to shut down}
  file_close (conn);                   {close connection to the serial line}
  end.
