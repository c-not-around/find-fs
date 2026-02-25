unit UFileIcon;


interface


{$reference 'System.Drawing.dll'}


uses System.Drawing;


function GetFileIcon(fname: string): Icon;


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
  

function SHGetFileInfo(pszPath: string; dwFileAttributes: longword; var psfi: SHFILEINFO; cbSizeFileInfo, uFlags: longword): IntPtr;
external 'shell32.dll' name 'SHGetFileInfo';

function DestroyIcon(hIcon: IntPtr): integer;
external 'User32.dll' name 'DestroyIcon';


function GetFileIcon(fname: string): Icon;
begin
  var shinfo := new SHFILEINFO();
  SHGetFileInfo(fname, $80, shinfo, Marshal.SizeOf(shinfo), $000000100 or $000000001);
  result := Icon.FromHandle(shinfo.hIcon).Clone() as Icon;
  DestroyIcon(shinfo.hIcon);
end;


end.