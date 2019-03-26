{   Public include file for the USBCAN library.  This library provides a
*   system-independent interface to a Embed Inc CAN controller that communicates
*   to the processor running this code via USB.
}
const
  usbcan_subsys_k = -56;               {subsystem ID for this library}
  usbcan_obufsz_k = 64;                {max bytes output buffer can hold}
{
*   Status codes unique to the USBCAN subsystem.
}
  usbcan_stat_namdevb_k = 1;           {named device found but was busy}
  usbcan_stat_namdevnf_k = 2;          {no device found of the specified name}
  usbcan_stat_devbusy_k = 3;           {found devices but all were busy}
  usbcan_stat_nodev_k = 4;             {no device found}
  usbcan_stat_tinit_k = 5;             {timed out waiting for initial communication}
  usbcan_stat_rspbad_k = 6;            {received unexpected response opcode}
{
*   Derived constants.
}
  usbcan_obuflast_k = usbcan_obufsz_k - 1; {last valid output buffer index}

type
  usbcan_dev_p_t = ^usbcan_dev_t;
  usbcan_dev_t = record                {info about one known USBCAN device list entry}
    next_p: usbcan_dev_p_t;            {pointer to next list entry}
    name: string_var80_t;              {user-settable name string}
    path: string_treename_t;           {system device pathname}
    end;

  usbcan_devs_t = record               {list of known devices connected to this system}
    mem_p: util_mem_context_p_t;       {pointer to memory context for all list memory}
    n: sys_int_machine_t;              {number of devices in the list}
    list_p: usbcan_dev_p_t;            {pointer to first list entry}
    last_p: usbcan_dev_p_t;            {pointer to last list entry}
    end;

  usbcan_fw_t = record                 {device firmware info}
    typ: sys_int_machine_t;            {1-N firmware type ID}
    ver: sys_int_machine_t;            {1-N firmware version number}
    seq: sys_int_machine_t;            {1-N firmware sequence number}
    end;

  usbcan_p_t = ^usbcan_t;
  usbcan_t = record                    {state for one use of this library}
    name: string_var80_t;              {USBCAN user-settable device name}
    mem_p: util_mem_context_p_t;       {points to context for all dynamic memory}
    conn: file_conn_t;                 {connection to the system device}
    thread_in: sys_sys_thread_id_t;    {ID of input reading thread}
    fw: usbcan_fw_t;                   {device firmware information}
    ready: sys_sys_event_id_t;         {event signalled when ready for operation}
    inq: can_queue_t;                  {queue of received CAN frames}
    lock_out: sys_sys_threadlock_t;    {thread interlock for OBUF output buffer}
    obuf:                              {output bytes not yet sent to the device}
      array[0..usbcan_obuflast_k] of int8u_t;
    nobuf: sys_int_machine_t;          {number of output bytes in OBUF}
    istat: sys_err_t;                  {error status from background thread failure}
    open: boolean;                     {connection to device is open}
    err: boolean;                      {error on background thread, ISTAT set}
    quit: boolean;                     {trying to close this use of the library}
    end;
{
*   Library entry points.
}
procedure usbcan_close (               {end use of this library}
  in out  uc: usbcan_t;                {state for this use of the library}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure usbcan_devs_dealloc (        {deallocate resources associated with devices list}
  in out  devs: usbcan_devs_t);        {list to deallocate resources of, returned unusable}
  val_param; extern;

procedure usbcan_devs_get (            {get list of all USBCAN devices connected to system}
  in out  mem: util_mem_context_t;     {parent context for list memory}
  out     devs: usbcan_devs_t);        {list to create and initialize}
  val_param; extern;

function usbcan_frame_recv (           {get next CAN frame}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      tout: real;                  {timeout seconds or SYS_TIMEOUT_xxx_k}
  out     frame: can_frame_t;          {CAN frame if function returns TRUE}
  out     stat: sys_err_t)             {completion status}
  :boolean;                            {TRUE with frame, FALSE with timeout or error}
  val_param; extern;

function usbcan_frame_avail (          {find whether received CAN frame available}
  in out  uc: usbcan_t)                {state for this use of the library}
  :boolean;                            {CAN frame is immediately available}
  val_param; extern;

procedure usbcan_frame_send (          {send CAN frame}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      frame: can_frame_t;          {the CAN frame to send}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure usbcan_init (                {init library state}
  out     uc: usbcan_t);               {returned initialized descriptor}
  val_param; extern;

procedure usbcan_open (                {open library use according to settings in UC}
  in out  uc: usbcan_t;                {library use state, returned initialized}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;
