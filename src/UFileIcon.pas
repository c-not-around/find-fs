unit UFileIcon;


interface


{$reference 'System.Drawing.dll'}


uses System.Drawing;


function GetFileIcon(fname: string; cache: boolean := true): System.Drawing.Icon;


implementation


uses System;
uses System.Runtime;
uses System.Runtime.InteropServices;


type
  [StructLayout(LayoutKind.Sequential)]
  SHFILEINFO = record
    hIcon: IntPtr;
    iIcon: IntPtr;
    dwAttributes: longword;
    [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]
    szDisplayName: string;
    [MarshalAs(UnmanagedType.ByValTStr,SizeConst=80)]
    szTypeName: string;
  end;
  
  SHGFI =
  (
    ICON              = $000000100, // SHGFI_ICON
    DISPLAYNAME       = $000000200, // SHGFI_DISPLAYNAME
    TYPENAME          = $000000400, // SHGFI_TYPENAME
    ATTRIBUTES        = $000000800, // SHGFI_ATTRIBUTES
    ICONLOCATION      = $000001000, // SHGFI_ICONLOCATION
    EXETYPE           = $000002000, // SHGFI_EXETYPE
    SYSICONINDEX      = $000004000, // SHGFI_SYSICONINDEX
    LINKOVERLAY       = $000008000, // SHGFI_LINKOVERLAY
    LARGEICON         = $000000000, // SHGFI_LARGEICON
    SMALLICON         = $000000001, // SHGFI_SMALLICON
    OPENICON          = $000000002, // SHGFI_OPENICON
    SHELLICONSIZE     = $000000004, // SHGFI_SHELLICONSIZE
    PIDL              = $000000008, // SHGFI_PIDL
    USEFILEATTRIBUTES = $000000010, // SHGFI_USEFILEATTRIBUTES
    ADDOVERLAYS       = $000000020, // SHGFI_ADDOVERLAYS
    OVERLAYINDEX      = $000000040  // SHGFI_OVERLAYINDEX
  );
  

function SHGetFileInfo(pszPath: string; dwFileAttributes: longword; var psfi: SHFILEINFO; cbSizeFileInfo, uFlags: longword): IntPtr;
external 'shell32.dll' name 'SHGetFileInfo';

function DestroyIcon(hIcon: IntPtr): integer;
external 'User32.dll' name 'DestroyIcon';


function GetFileIcon(fname: string; cache: boolean): System.Drawing.Icon;
begin
  var flags := SHGFI.ICON or SHGFI.SMALLICON;
  if cache then
    flags := flags or SHGFI.USEFILEATTRIBUTES;
    
  var shinfo := new SHFILEINFO();
  var status := SHGetFileInfo(fname, $80, shinfo, Marshal.SizeOf(shinfo), longword(flags));
  
  if (status <> IntPtr.Zero) and (shinfo.hIcon <> IntPtr.Zero) then
   try
     result := System.Drawing.Icon.FromHandle(shinfo.hIcon).Clone() as System.Drawing.Icon;
     exit;
   finally
     DestroyIcon(shinfo.hIcon);
   end;
  
  result := nil;
end;


end.