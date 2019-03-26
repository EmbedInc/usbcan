{   Routines that manipulate device lists.
}
module usbcan_devs;
define usbcan_devs_create;
define usbcan_devs_add;
define usbcan_devs_get;
define usbcan_devs_dealloc;
%include 'usbcan2.ins.pas';
{
********************************************************************************
*
*   Subroutine USBCAN_DEVS_CREATE (DEVS)
*
*   Create a new devices list and initialize it to empty.  System resources may
*   be allocated until USBCAN_DEVS_DEALLOC is called.
}
procedure usbcan_devs_create (         {create new empty devices list}
  in out  mem: util_mem_context_t;     {parent context for list memory}
  out     devs: usbcan_devs_t);        {list to create and initialize}
  val_param;

begin
  util_mem_context_get (mem, devs.mem_p); {create memory context for the new list}
  devs.n := 0;                         {init the list to empty}
  devs.list_p := nil;
  devs.last_p := nil;
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_DEVS_ADD (DEVS)
*
*   Create a new entry at the end of the devices list and initialize it to
*   default or benign values to the extent possible.  The new entry will be
*   pointed to by DEVS.LAST_P.
}
procedure usbcan_devs_add (            {add blank entry to end of devices list}
  in out  devs: usbcan_devs_t);        {list to add entry to, new entry will be last}
  val_param;

var
  dev_p: usbcan_dev_p_t;               {pointer to new devices list entry}

begin
  util_mem_grab (sizeof(dev_p^), devs.mem_p^, false, dev_p); {alloc mem for new entry}

  dev_p^.next_p := nil;                {no entry follows this one}
  dev_p^.name.max := size_char(dev_p^.name.str); {init device name to empty}
  dev_p^.name.len := 0;
  dev_p^.path.max := size_char(dev_p^.path.str); {init system device pathname to empty}
  dev_p^.path.len := 0;

  if devs.last_p = nil
    then begin                         {this is first list entry}
      devs.list_p := dev_p;
      end
    else begin                         {adding to end of existing list}
      devs.last_p^.next_p := dev_p;
      end
    ;
  devs.last_p := dev_p;                {update pointer to last list entry}
  devs.n := devs.n + 1;                {count one more list entry}
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_DEVS_GET (MEM, DEVS)
*
*   Get the list of all USBCAN devices connected to the system.  DEVS will be
*   newly created, and may tie up system resources until the list is deleted
*   by calling USBCAN_DEVS_DEALLOC.
}
procedure usbcan_devs_get (            {get list of all USBCAN devices connected to system}
  in out  mem: util_mem_context_t;     {parent context for list memory}
  out     devs: usbcan_devs_t);        {list to create and initialize}
  val_param;

begin
  usbcan_devs_create (mem, devs);      {create new empty list}
  usbcan_sys_enum (devs);              {enumerate all devices and add them to the list}
  end;
{
********************************************************************************
*
*   Subroutine USBCAN_DEVS_DEALLOC (DEVS)
*
*   Deallocate all system resources associated with the devices list DEVS.  The
*   list will be returned unusable.  The list must be re-created before it can
*   be used again.
}
procedure usbcan_devs_dealloc (        {deallocate resources associated with devices list}
  in out  devs: usbcan_devs_t);        {list to deallocate resources of, returned unusable}
  val_param;

begin
  util_mem_context_del (devs.mem_p);   {deallocate all dynamic memory used by the list}
  devs.n := 0;
  devs.list_p := nil;
  devs.last_p := nil;
  end;
