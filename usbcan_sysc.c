//   System dependent routines for accessing a USBCAN USB device that also need
//   access to system include files.  The application interface presented here
//   must be implemented separately per target operating system.
//
//   This version is for Windows 2000 and later.  It assumes the Microsoft
//   visual C++ compiler version 6 using the C (not C++) language.
//
#include <wtypes.h>
#include <winbase.h>
#include <stdio.h>
#include <io.h>
#include <setupapi.h>
#include <initguid.h>
#include <winioctl.h>

#include "sys.h"
#include "util.h"
#include "string.h"
#include "file.h"

#include "usbcan_driver.h"
#include "can.h"
#include "can3.h"
#include "usbcan.h"

//******************************************************************************
//
//   Subroutine USBCAN_SYS_ENUM (DEVS)
//
//   Add all the USBCAN devices to the list of devices in DEVS.
//
void usbcan_sys_enum (                 //enumerate USBCAN devices and add to list of devices
  usbcan_devs_t *devs) {               //devices list to add to

LPGUID guid_p;                         //pointer to GUID used by our driver
HDEVINFO devlist;                      //handle to list of devices with our GUID
BOOL devlist_alloc;                    //data allocated to devlist handle
INT devn;                              //current 0-N device list entry number
SP_DEVICE_INTERFACE_DATA devinfo;      //info about one of our USB devices
BOOL succ;                             //success flag returned by some functions
DWORD sz;                              //memory size
PSP_DEVICE_INTERFACE_DETAIL_DATA devpath_p; //points to descriptor containing device path
BOOL devpath_alloc;                    //device pathname descriptor allocated
SP_DEVINFO_DATA devnode;               //descriptor containing dev-node info
string_treename_t tnam;                //scratch pathname
HANDLE h;                              //temp handle
//
//   Executable code for subroutine USBCAN_SYS_ENUM.
//
  tnam.max = sizeof(tnam.str);         //init local var string
  guid_p = (LPGUID) &usbcan_guid;      //make and save pointer to our GUID
  devlist_alloc = FALSE;               //indicate devs list handle has no data allocated
  devpath_alloc = FALSE;               //device pathname descriptor not allocated

  devlist = SetupDiGetClassDevs (      //get handle to list of devices with our GUID
    guid_p,                            //pointer to our GUID
    NULL,                              //no special pattern to match
    NULL,                              //handle to top level GUI window, not used
    ( DIGCF_PRESENT |                  //only devices currently present
      DIGCF_DEVICEINTERFACE) );        //GUID specifies an interface class, not setup class
  if (devlist == INVALID_HANDLE_VALUE) goto done_list;
  devlist_alloc = TRUE;                //indicate devices list handle has data allocated
//
//   Loop thru all devices of our type that are currently connected.
//
  devn = -1;                           //init to before first list entry
  devinfo.cbSize = sizeof(SP_DEVICE_INTERFACE_DATA); //set size of this structure

next_listent:                          //back here to try next list entry
  devn++;                              //make 0-N list entry number for this pass
  if (devpath_alloc) {
    free (devpath_p);                  //deallocate any previous device pathname descriptor
    devpath_alloc = FALSE;
    }

  succ = SetupDiEnumDeviceInterfaces ( //get info on one device in the list
    devlist,                           //handle to the list of devices
    NULL,                              //no extra info to constrain the search
    guid_p,                            //pointer to GUID of our device
    devn,                              //0-N number of device to get info about
    &devinfo);                         //returned device info
  if (!succ) goto done_list;           //didn't get info about this device number ?
//
//   Get the Win32 pathname for this device.  The function
//   SetupDiGetDeviceInterfaceDetail is called twice.  The first time to find
//   the size of the buffer needed to hold all the return information, and the
//   second time to get the return information.
//
  succ = SetupDiGetDeviceInterfaceDetail ( //find size of buffer to hold all the data
    devlist,                           //handle to list of our USB devices
    &devinfo,                          //info about the selected device
    NULL,                              //no detailed information output buffer supplied
    0,                                 //output buffer size
    &sz,                               //required buffer size
    NULL);                             //no dev-node info buffer supplied
  if (!succ) {
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER) goto next_listent;
    }
  //
  //   SZ is the size of the buffer required to hold all the returned info.
  //
  devpath_p = malloc (sz);             //allocate the device pathname descriptor
  devpath_alloc = TRUE;                //indicate device pathname descriptor allocated
  devpath_p->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA);
  devnode.cbSize = sizeof(SP_DEVINFO_DATA);

  succ = SetupDiGetDeviceInterfaceDetail ( //get detail information on this device
    devlist,                           //handle to list of our USB devices
    &devinfo,                          //info about the selected device
    devpath_p,                         //returned device pathname descriptor
    sz,                                //output buffer size
    NULL,                              //no required size return variable supplied
    &devnode);                         //returned dev-node info (not used)
  if (!succ) goto next_listent;
//
//   The pathname to this device is in devpath_p->DevicePath.
//
//   Now get the device's user-settable name.
//
  string_vstring (&tnam, &devpath_p->DevicePath, -1); //make var string dev pathname
  string_appendn (&tnam, "\\INFO", 5); //make device pathname for getting the name
  string_terminate_null (&tnam);       //make sure STR field contains termination NULL

  h = CreateFile (                     //try to open this device
    tnam.str,                          //pathname of object to open
    GENERIC_READ | GENERIC_WRITE,      //required for opening "info" device
    FILE_SHARE_READ | FILE_SHARE_WRITE, //required for opening "info" device
    NULL,                              //no security attributes specified
    OPEN_EXISTING,                     //device must already exist
    0,                                 //no special attributes
    NULL);                             //no template attributes file supplied
  if (h == INVALID_HANDLE_VALUE) {     //attempt to open "\info" device failed ?
    goto next_listent;
    }

  succ = DeviceIoControl (             //get the user-settable name of this device
    h,                                 //handle to the I/O connection
    IOCTL_USBCAN_GET_FWID,             //control code for getting name
    NULL, 0,                           //no data passed to device
    tnam.str,                          //buffer to return data into
    tnam.max,                          //max size data allowed to return
    &sz,                               //number of bytes actually returned
    NULL);                             //no overlapped I/O structure supplied
  CloseHandle (h);                     //done with "info" connection to this device
  if (!succ) goto next_listent;
  tnam.len = sz;                       //set received name string length
//
//   A new device was found.  It's system pathname is in devpath_p->DevicePath
//   and its user-settable name is in TNAM.
//
  usbcan_devs_add (devs);              //add new entry to end of devices list
  string_copy (&tnam, &devs->last_p->name); //set the user name
  string_vstring (&devs->last_p->path, &devpath_p->DevicePath, -1); //set system pathname
  goto next_listent;                   //back to check out next list entry
//
//   Done scanning the devices list.
//
done_list:                             //common exit point
  if (devpath_alloc) {
    free (devpath_p);                  //deallocate device pathname descriptor
    }
  if (devlist_alloc) {
    SetupDiDestroyDeviceInfoList (devlist); //try to deallocate devices list
    }
  }

//******************************************************************************
//
//   Subroutine USBCAN_SYS_OPEN (dev, hout, hin, stat)
//
//   Open the device identified by DEV.  HOUT and HIN are the returned handles
//   to the output and input data pipes.
//
void usbcan_sys_open (                 //open device and return handles
  usbcan_dev_t *dev,                   //info about the device to open, must be USB type
  HANDLE *hout,                        //returned handle to output bulk data pipe
  HANDLE *hin,                         //returned handle to input bulk data pipe
  sys_err_t *stat) {                   //returned completion status

string_treename_t tnam;                //scratch pathname
//
//   Executable code for subroutine USBCAN_SYS_OPEN.
//
  tnam.max = sizeof(tnam.str);         //init local var string
  sys_error_none (stat);               //init to not returning with error
  string_copy (&dev->path, &tnam);     //make local copy of device full pathname
  string_terminate_null (&tnam);       //make sure it is NULL terminated

  *hout = CreateFile (                 //try to open this device
    tnam.str,                          //pathname of object to open
    GENERIC_READ | GENERIC_WRITE,      //will read and write to the device
    0,                                 //open for exclusive access to the device
    NULL,                              //no security attributes specified
    OPEN_EXISTING,                     //device must already exist
    FILE_FLAG_OVERLAPPED,              //we will be using overlapped I/O
    NULL);                             //no template attributes file supplied
  if (*hout == INVALID_HANDLE_VALUE) { //unable to open the device ?
    stat->sys = GetLastError ();
    return;
    }

  *hin = *hout;                        //same handle for reading and writing
  }
