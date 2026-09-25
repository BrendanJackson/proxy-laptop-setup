<#
Fix-ScreenRotation.ps1 -- force every attached display back to landscape
(0 degrees) via the same Win32 display API Windows itself uses, bypassing
the Ctrl+Alt+Arrow hotkeys entirely. For when a display comes back rotated
after sleep/restart and the hotkeys (Ctrl+Alt+Up = landscape, Down = upside
down, Left/Right = portrait) don't fix it -- that combo depends on a
driver-level hotkey handler that can be disabled or just not respond; this
calls ChangeDisplaySettingsEx directly instead of relying on it.

Usage:
    .\Fix-ScreenRotation.ps1

No admin required -- display orientation is a per-session setting.

If this doesn't fix it: the driver may be reasserting its own rotation on
top of this (some Intel/AMD/Nvidia control panels do). Try, in order:
  1. Right-click the desktop -> Graphics Options / Intel Graphics Settings /
     AMD Radeon Settings -> Rotation -> 0 degrees (Intel/AMD iGPUs add this
     to the desktop right-click menu directly).
  2. Settings -> System -> Display -> Display orientation -> Landscape.
#>

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class DisplayRotationFix {
    private const int CCHDEVICENAME = 32;
    private const int CCHFORMNAME = 32;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHDEVICENAME)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHFORMNAME)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern int ChangeDisplaySettingsEx(string deviceName, ref DEVMODE devMode, IntPtr hwnd, int flags, IntPtr param);

    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int DMDO_DEFAULT = 0;
    public const int DM_DISPLAYORIENTATION = 0x00000080;
    public const int CDS_UPDATEREGISTRY = 0x00000001;
    public const int CDS_RESET = 0x40000000;
    public const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x1;

    public static string FixAll() {
        var results = new System.Text.StringBuilder();
        uint devNum = 0;
        bool any = false;
        while (true) {
            var dd = new DISPLAY_DEVICE();
            dd.cb = Marshal.SizeOf(dd);
            if (!EnumDisplayDevices(null, devNum, ref dd, 0)) break;
            devNum++;
            if ((dd.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) == 0) continue;

            var dm = new DEVMODE();
            dm.dmSize = (short)Marshal.SizeOf(dm);
            if (!EnumDisplaySettings(dd.DeviceName, ENUM_CURRENT_SETTINGS, ref dm)) {
                results.AppendLine(dd.DeviceName + ": could not read current settings");
                continue;
            }
            any = true;
            int before = dm.dmDisplayOrientation;
            dm.dmDisplayOrientation = DMDO_DEFAULT;
            dm.dmFields = DM_DISPLAYORIENTATION;
            int r = ChangeDisplaySettingsEx(dd.DeviceName, ref dm, IntPtr.Zero, CDS_UPDATEREGISTRY | CDS_RESET, IntPtr.Zero);
            results.AppendLine(dd.DeviceName + ": was orientation " + before + " (0=normal,1=90,2=180,3=270), apply result " + r + " (0 = success)");
        }
        if (!any) results.AppendLine("No attached displays found via EnumDisplayDevices.");
        return results.ToString();
    }
}
"@

Write-Host "Resetting display orientation to landscape (0 degrees) on every attached display..." -ForegroundColor Cyan
Write-Host ([DisplayRotationFix]::FixAll())
Write-Host "`nStill upside down? The driver may be reasserting its own rotation on top of this." -ForegroundColor Yellow
Write-Host "Try: right-click desktop -> Graphics Options / Intel Graphics Settings -> Rotation -> 0 degrees" -ForegroundColor Yellow
Write-Host "Or:  Settings -> System -> Display -> Display orientation -> Landscape" -ForegroundColor Yellow
