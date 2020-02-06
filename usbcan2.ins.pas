{   Private include file for the USBCAN library.
}
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';
%include 'pic.ins.pas';
%include 'can.ins.pas';
%include 'can3.ins.pas';
%include 'usbcan.ins.pas';

type
  usbcan_cmd_k = (                     {command opcodes to a USBCAN device}
    usbcan_cmd_nop_k = 0,              {NOP}
    usbcan_cmd_fwver_k = 1,            {request firmware version info}
    usbcan_cmd_nameset_k = 2,          {set unit name}
    usbcan_cmd_nameget_k = 3,          {request unit name}
    usbcan_cmd_sends_k = 9,            {send standard CAN data frame}
    usbcan_cmd_sende_k = 10,           {send extended CAN data frame}
    usbcan_cmd_sendsr_k = 11,          {send standard CAN remote request frame}
    usbcan_cmd_sender_k = 12);         {send extended CAN remote request frame}

  usbcan_rsp_k = (                     {response opcodes from a USBCAN device}
    usbcan_rsp_nop_k = 0,              {NOP}
    usbcan_rsp_fwver_k = 1,            {firmware version info}
    usbcan_rsp_name_k = 2,             {unit name}
    usbcan_rsp_cspi_k = 3,             {CAN controller SPI byte}
    usbcan_rsp_canfr_k = 4);           {received CAN frame}

procedure usbcan_devs_add (            {add blank entry to end of devices list}
  in out  devs: usbcan_devs_t);        {list to add entry to, new entry will be last}
  val_param; extern;

procedure usbcan_devs_create (         {create new empty devices list}
  in out  mem: util_mem_context_t;     {parent context for list memory}
  out     devs: usbcan_devs_t);        {list to create and initialize}
  val_param; extern;

procedure usbcan_thread_in (           {root routine of input reading thread}
  in      arg: sys_int_adr_t);         {address of library state}
  val_param; extern;

procedure usbcan_out_byte (            {send byte to the device, may be buffered}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      b: sys_int_conv8_t;          {byte is in low 8 bits}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure usbcan_out_flush (           {send all buffered output data to the device}
  in out  uc: usbcan_t;                {state for this use of the library}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure usbcan_out_i16 (             {send 16 bit integer to the device}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      w: sys_int_conv16_t;         {word is in low 16 bits}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure usbcan_out_i32 (             {send 32 bit integer to the device}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      w: sys_int_conv32_t;         {32 bit word to send}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure usbcan_out_lock (            {acquire exclusive access to sending to device}
  in out  uc: usbcan_t);               {state for this use of the library}
  val_param; extern;

procedure usbcan_out_opc (             {send command opcode to the device}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      opc: usbcan_cmd_k;           {the command opcode}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure usbcan_out_unlock (          {release lock on output device}
  in out  uc: usbcan_t);               {state for this use of the library}
  val_param; extern;

procedure usbcan_stat_check (          {abort thread on error}
  in out  uc: usbcan_t;                {state for this use of the library}
  in      stat: sys_err_t);            {status to check}
  val_param; extern;

procedure usbcan_sys_enum (            {add known USBCAN devices to list}
 in out  devs: usbcan_devs_t);         {list to add devices to}
 val_param; extern;

procedure usbcan_sys_open_name (       {open connection to named USBCAN device}
  in      name: univ string_var_arg_t; {name of device to open, opens first on empty}
  out     conn: file_conn_t;           {returned connection to the device}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure usbcan_sys_read (            {read next chunk of bytes from device}
  in out  conn: file_conn_t;           {connection to the device}
  in      ilen: sys_int_adr_t;         {max number of machine adr increments to read}
  out     buf: univ char;              {returned data}
  out     olen: sys_int_adr_t;         {number of machine adresses actually read}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure usbcan_sys_write (           {send data to a device}
  in out  conn: file_conn_t;           {connection to the device}
  in      buf: univ char;              {data to write}
  in      len: sys_int_adr_t;          {number of machine adr increments to write}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;
