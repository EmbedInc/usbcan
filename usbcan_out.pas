{   Routines for sending data to the device.
}
module usbcan_out;
define usbcan_out_lock;
define usbcan_out_unlock;
define usbcan_out_flush;
define usbcan_out_byte;
define usbcan_out_opc;
define usbcan_out_i16;
define usbcan_out_i32;
%include 'usbcan2.ins.pas';
{
********************************************************************************
*
*   Subroutine USBCAN_OUT_LOCK (UC)
*
*   Acquire the exclusive lock on the output buffer.  This lock should be held
*   whenever writing output data or accessing the output buffer.
}
procedure usbcan_out_lock (            {acquire exclusive access to sending to device}
  in out  uc: usbcan_t);               {state for this use of the library}
  val_param;

begin
  sys_thread_lock_enter (uc.lock_out);
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_OUT_UNLOCK (UC)
*
*   Release the exclusive lock on the output buffer that was acquired with
*   USBCAN_OUT_LOCK.
}
procedure usbcan_out_unlock (          {release lock on output device}
  in out  uc: usbcan_t);               {state for this use of the library}
  val_param;

begin
  sys_thread_lock_leave (uc.lock_out);
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_OUT_FLUSH (UC, STAT)
*
*   Send any data in the output buffer to the device.  The output buffer is
*   guaranteed to be empty when this routine returns without error.  The output
*   lock must be held when this routine is called.
}
procedure usbcan_out_flush (           {send all buffered output data to the device}
  in out  uc: usbcan_t;                {state for this use of the library}
  out     stat: sys_err_t);            {completion status}
  val_param;

begin
  sys_error_none (stat);               {init to no error encountered}

  if uc.nobuf > 0 then begin           {there is data to send ?}
    usbcan_sys_write (                 {send the data}
      uc.conn,                         {connection to the device}
      uc.obuf,                         {buffer of bytes to send}
      uc.nobuf,                        {number of bytes to send}
      stat);
    end;

  uc.nobuf := 0;                       {reset the output buffer to empty}
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_OUT_BYTE (UC, B, STAT)
*
*   Send the byte in the low bits of B to the output device.  The byte is
*   actually buffered and may not be sent until the next FLUSH call.
*
*   The output lock must be held when this routine is called.
*
*   The output buffer is maintained so that there is always room for at least
*   one more byte.  If adding a byte to the buffer fills it, then it is flushed
*   immediately.
}
procedure usbcan_out_byte (            {send byte to the device, may be buffered}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      b: sys_int_conv8_t;          {byte is in low 8 bits}
  out     stat: sys_err_t);            {completion status}
  val_param;

begin
  sys_error_none (stat);               {init to no error encountered}

  uc.obuf[uc.nobuf] := b & 255;        {stuff the byte into the buffer}
  uc.nobuf := uc.nobuf + 1;
  if uc.nobuf >= usbcan_obufsz_k then begin {buffer is now full ?}
    usbcan_out_flush (uc, stat);       {flush the buffer}
    end;
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_OUT_OPC (UC, OPC, STAT)
*
*   Send the command opcode OPC to the device.  The opcode may be buffered and
*   is not guaranteed to be sent until the next FLUSH call.
*
*   The output lock must be held when this routine is called.
}
procedure usbcan_out_opc (             {send command opcode to the device}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      opc: usbcan_cmd_k;           {the command opcode}
  out     stat: sys_err_t);            {completion status}
  val_param;

begin
  usbcan_out_byte (uc, ord(opc), stat);
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_OUT_I16 (UC, W, STAT)
*
*   Send the word in the low 16 bits of W to the device.  The data may be
*   buffered and is not guaranteed to be sent until the next FLUSH call.
*
*   The output lock must be held when this routine is called.
}
procedure usbcan_out_i16 (             {send 16 bit integer to the device}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      w: sys_int_conv16_t;         {word is in low 16 bits}
  out     stat: sys_err_t);            {completion status}
  val_param;

begin
  usbcan_out_byte (uc, w, stat);       {send the low byte}
  if sys_error(stat) then return;
  usbcan_out_byte (uc, rshft(w, 8), stat); {send the high byte}
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_OUT_I32 (UC, W, STAT)
*
*   Send the word in the low 32 bits of W to the device.  The data may be
*   buffered and is not guaranteed to be sent until the next FLUSH call.
*
*   The output lock must be held when this routine is called.
}
procedure usbcan_out_i32 (             {send 32 bit integer to the device}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      w: sys_int_conv32_t;         {32 bit word to send}
  out     stat: sys_err_t);            {completion status}
  val_param;

begin
  usbcan_out_byte (uc, w, stat);       {send the low byte}
  if sys_error(stat) then return;
  usbcan_out_byte (uc, rshft(w, 8), stat); {send byte 1}
  if sys_error(stat) then return;
  usbcan_out_byte (uc, rshft(w, 16), stat); {send byte 2}
  if sys_error(stat) then return;
  usbcan_out_byte (uc, rshft(w, 24), stat); {send the high byte}
  end;
