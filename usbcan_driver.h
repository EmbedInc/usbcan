//   Common include file for the USBCAN device driver and the
//   applications routines that must interface with it directly.
//
#ifndef _USBCAN_USER_H
#define _USBCAN_USER_H

#include <initguid.h>

// {6310356F-28BE-4678-AB3A-E642B017E40A}
DEFINE_GUID(usbcan_guid,
0x6310356f, 0x28be, 0x4678, 0xab, 0x3a, 0xe6, 0x42, 0xb0, 0x17, 0xe4, 0xa);

#define USBCAN_IOCTL_INDEX 0x0000

// IOCTL to get the firmware ID string
// returns unterminated string in output buffer
#define IOCTL_USBCAN_GET_FWID CTL_CODE( \
  FILE_DEVICE_UNKNOWN, \
  USBCAN_IOCTL_INDEX + 1, \
  METHOD_BUFFERED, \
  FILE_ANY_ACCESS)

#define FWID_STRING_SIZE (80)          // maximum length of the firmware ID string

#endif
