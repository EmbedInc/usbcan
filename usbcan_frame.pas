{   Routines that send and receive CAN frames.
}
module usbcan_frame;
define usbcan_frame_send;
define usbcan_frame_avail;
define usbcan_frame_recv;
%include 'usbcan2.ins.pas';
{
********************************************************************************
*
*   Subroutine USBCAN_FRAME_SEND (UC, FRAME, STAT)
*
*   Transmit the CAN frame in FRAME.  This routine may return before the frame
*   is physically transmitted.
}
procedure usbcan_frame_send (          {send CAN frame}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      frame: can_frame_t;          {the CAN frame to send}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  ndat: sys_int_machine_t;             {number of data bytes to send}
  ii: sys_int_machine_t;               {scratch integer and loop counter}
  stat2: sys_err_t;

label
  done_dat, abort;

begin
  usbcan_out_lock (uc);                {acquire exclusive lock on sending to the device}

  if can_frflag_ext_k in frame.flags
    then begin                         {extended frame}
      if can_frflag_rtr_k in frame.flags
        then begin                     {extended remote request frame}
          usbcan_out_opc (uc, usbcan_cmd_sender_k, stat); {opcode}
          if sys_error(stat) then goto abort;
          usbcan_out_i32 (uc, frame.id, stat); {29 bit frame ID}
          if sys_error(stat) then goto abort;
          goto done_dat;               {this frame has no data bytes}
          end
        else begin                     {extended data frame}
          usbcan_out_opc (uc, usbcan_cmd_sende_k, stat); {opcode}
          if sys_error(stat) then goto abort;
          usbcan_out_i32 (uc, frame.id, stat); {29 bit frame ID}
          if sys_error(stat) then goto abort;
          end
        ;
      end
    else begin                         {standard frame}
      if can_frflag_rtr_k in frame.flags
        then begin                     {standard remote request frame}
          usbcan_out_opc (uc, usbcan_cmd_sendsr_k, stat); {opcode}
          if sys_error(stat) then goto abort;
          usbcan_out_i16 (uc, frame.id, stat); {11 bit frame ID}
          if sys_error(stat) then goto abort;
          goto done_dat;               {this frame has no data bytes}
          end
        else begin                     {standard data frame}
          usbcan_out_opc (uc, usbcan_cmd_sends_k, stat); {opcode}
          if sys_error(stat) then goto abort;
          usbcan_out_i16 (uc, frame.id, stat); {11 bit frame ID}
          if sys_error(stat) then goto abort;
          end
        ;
      end
    ;
  ndat := max(0, min(8, frame.ndat));  {make valid number of data bytes}
  usbcan_out_byte (uc, ndat, stat);    {send number of data bytes to follow}
  if sys_error(stat) then goto abort;
  for ii := 0 to ndat-1 do begin       {once for each data byte}
    usbcan_out_byte (uc, frame.dat[ii], stat); {send this data byte}
    end;
done_dat:                              {done sending data bytes, if any}

  usbcan_out_flush (uc, stat);         {make sure command gets sent}
  usbcan_out_unlock (uc);              {release lock on sending to the device}
  return;                              {normal return point}

abort:                                 {jump here on hard error, STAT already set}
  usbcan_out_flush (uc, stat2);        {make sure command gets sent}
  usbcan_out_unlock (uc);              {release lock on sending to the device}
  end;
{
********************************************************************************
*
*   Function USBCAN_FRAME_AVAIL (UC)
*
*   Indicate whether a received CAN frame is immediately available.  When this
*   routine returns TRUE, the next call to USBCAN_FRAME_RECV will return with a
*   CAN frame without waiting.
}
function usbcan_frame_avail (          {find whether received CAN frame available}
  in out  uc: usbcan_t)                {state for this use of the library}
  :boolean;                            {CAN frame is immediately available}
  val_param;

begin
  usbcan_frame_avail := can_queue_ent_avail (uc.inq);
  end;
{
********************************************************************************
*
*   Function USBCAN_FRAME_RECV (UC, TOUT, FRAME, STAT)
*
*   Get the next received CAN frame into FRAME.  TOUT is the maximum seconds to
*   wait for a frame to be available.  The function returns TRUE when returning
*   with a frame.  It returns FALSE when no frame was available within the
*   timeout or on a hard error.  The contents of FRAME is undefined when the
*   function return FALSE.
}
function usbcan_frame_recv (           {get next CAN frame}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      tout: real;                  {timeout seconds or SYS_TIMEOUT_xxx_k}
  out     frame: can_frame_t;          {CAN frame if function returns TRUE}
  out     stat: sys_err_t)             {completion status}
  :boolean;                            {TRUE with frame, FALSE with timeout or error}
  val_param;

begin
  sys_error_none (stat);
  usbcan_frame_recv := can_queue_get (uc.inq, tout, frame);
  end;
