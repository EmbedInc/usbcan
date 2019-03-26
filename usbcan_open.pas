{   Routines for opening and closing a use of the USBCAN library.
}
module usbcan_open;
define usbcan_init;
define usbcan_open;
define usbcan_close;
%include 'usbcan2.ins.pas';
{
********************************************************************************
*
*   Subroutine USBCAN_INIT (UC)
*
*   Initialize the USBCAN library use state, UC.  This routine must be called
*   before UC is accessed in any way.  No system resources will be allocated,
*   UC will be in a consistent state for other operations, like setting the
*   device name and calling USBCAN_OPEN.
}
procedure usbcan_init (                {init library state}
  out     uc: usbcan_t);               {returned initialized descriptor}
  val_param;

begin
  uc.name.max := size_char(uc.name.str);
  uc.name.len := 0;
  uc.mem_p := nil;
  uc.fw.typ := 0;
  uc.fw.ver := 0;
  uc.fw.seq := 0;
  uc.nobuf := 0;
  sys_error_none (uc.istat);
  uc.open := false;
  uc.err := false;
  uc.quit := false;
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_OPEN (UC, STAT)
*
*   Open a use of the USBCAN library.  The library use state UC is updated
*   accordingly.  UC must have been previously initialized with USBCAN_INIT.
*   Some fields may be altered after it is initialized and this call.  The
*   alterable fields are:
*
*     NAME  -  The name of the CAN device to use.  Blank causes the first
*       compatible device that is found and not already in use to be used.  NAME
*       is initialized to blank.
*
*     MEM_P  -  Pointer to the context to use of all dynamically allocated
*       memory of the library use.  When NIL on entry, a new context will be
*       created immediately subordinate to the root context.  The memory context
*       will be deleted when this library use state is closed, regardless of
*       whether it was provided by the user or created in this routine.  MEM_P
*       is initialized to NIL.
*
*   If this routine fails, STAT is returned to indicate the reason, and UC is
*   returned initialized.
}
procedure usbcan_open (                {open library use according to settings in UC}
  in out  uc: usbcan_t;                {library use state to open}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  ev: sys_sys_event_id_t;              {scratch event}
  stat2: sys_err_t;                    {local return status to avoid corrupting STAT}

label
  abort0, abort2, abort3, abort4;

begin
  usbcan_sys_open_name (uc.name, uc.conn, stat); {open connection to the device}
  if sys_error(stat) then goto abort0;
  uc.open := true;                     {indicate the device connection is open}
  uc.quit := false;                    {init to not trying to shut down}

  if uc.mem_p = nil then begin         {no specific memory context provided}
    util_mem_context_get (util_top_mem_context, uc.mem_p); {create mem context subordinate to root}
    end;

  can_queue_init (uc.inq, uc.mem_p^);  {set up received CAN frames queue}

  sys_thread_lock_create (uc.lock_out, stat); {create interlock for output buffer}
  if sys_error(stat) then goto abort2;
  uc.nobuf := 0;                       {init the output buffer to empty}

  sys_error_none (uc.istat);           {init to no error in background thread}
  uc.err := false;
  sys_event_create_bool (uc.ready);    {create event signalled when input init done}
  sys_thread_create (                  {create input reading thread}
    addr(usbcan_thread_in),            {address of root thread routine}
    sys_int_adr_t(addr(uc)),           {argument is address of library state}
    uc.thread_in,                      {returned ID of the new thread}
    stat);
  if sys_error(stat) then goto abort3;

  if sys_event_wait_tout (             {wait for initial device communication to complete}
      uc.ready,                        {event to wait on}
      5.0,                             {maximum seconds to wait}
      stat) then begin
    if not sys_error(stat) then begin  {hit timeout, not a hard error ?}
      sys_stat_set (usbcan_subsys_k, usbcan_stat_tinit_k, stat);
      end;
    goto abort4;
    end;
  return;                              {normal return point}
{
*   Error exit points.  A error has occurred and STAT is indicating the error.
*   Higher abort points are jumped to with successively more system resources
*   allocated.
}
abort4:
  uc.quit := true;                     {tell thread we are trying to shut down}
  file_close (uc.conn);                {close connection to the device}
  uc.open := false;                    {indicate device connection not open}
  sys_thread_event_get (uc.thread_in, ev, stat2); {get event signalled on thread exit}
  if not sys_error(stat2) then begin
    discard( sys_event_wait_tout (ev, 2.0, stat2) ); {wait for thread exit or timeout}
    end;

abort3:
  sys_event_del_bool (uc.ready);       {delete event signalled when ready}
  sys_thread_lock_delete (uc.lock_out, stat2);

abort2:
  can_queue_release (uc.inq);          {release system resources of the CAN input queue}
  if uc.open then begin                {connection to the device is open ?}
    file_close (uc.conn);              {close the connection to the device}
    end;

abort0:                                {common abort exit point}
  if uc.mem_p <> nil then begin        {private memory context exists ?}
    util_mem_context_del (uc.mem_p);   {delete the memory context}
    end;
  usbcan_init (uc);                    {re-initialize the library state}
  end;
{
********************************************************************************
*
*   USBCAN_CLOSE (UC, STAT)
*
*   Close this use of the USBCAN library.  All system resources associated with
*   the use will be released, and the CAN device will be left available for
*   other applications to access.  No further I/O operations are allowed with
*   UC.  UC will be returned initialized.
}
procedure usbcan_close (               {end use of this library}
  in out  uc: usbcan_t;                {library use state, returned initialized}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  ev: sys_sys_event_id_t;              {scratch event}
  stat2: sys_err_t;                    {local return status to avoid corrupting STAT}

begin
  sys_error_none (stat);               {init to no error encountered}
  uc.quit := true;                     {tell thread we are trying to shut down}
  uc.inq.quit := true;

  usbcan_out_flush (uc, stat2);        {send any buffered output bytes}
  if sys_error(stat2) and (not sys_error(stat)) then begin
    stat := stat2;
    end;

  sys_thread_event_get (uc.thread_in, ev, stat2); {get event signalled on thread exit}
  file_close (uc.conn);                {close the connection to the device}
  if sys_error(stat2) and (not sys_error(stat)) then begin
    stat := stat2;
    end;
  if not sys_error(stat2) then begin
    discard( sys_event_wait_tout (ev, 0.5, stat2) ); {wait for thread exit or timeout}
    end;

  sys_event_del_bool (uc.ready);       {delete event signalled when ready}
  sys_thread_lock_delete (uc.lock_out, stat2); {delete output buffer lock}
  if sys_error(stat2) and (not sys_error(stat)) then begin
    stat := stat2;
    end;
  can_queue_release (uc.inq);          {release system resources of the CAN input queue}
  if uc.mem_p <> nil then begin        {private memory context exists ?}
    util_mem_context_del (uc.mem_p);   {delete the memory context}
    end;

  usbcan_init (uc);                    {re-initialize the library state}
  end;
