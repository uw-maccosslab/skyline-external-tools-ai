# Installing a Skyline tool

*Building a tool? This page is for **end users**. Developers should read the field guide instead:
[skyline-external-tools.md](skyline-external-tools.md).*

A short, friendly walkthrough for installing a packaged Skyline external tool — the kind that arrives
as a single `.zip` file — and running it inside Skyline. No coding required, and it applies to any
tool built from this repository.

## Before you start (prerequisites)

1. **Skyline or Skyline-daily**, installed and able to open your document. (Get it from
   [skyline.ms](https://skyline.ms) if you don't already have it.)
2. **The .NET 8.0 Desktop Runtime (x64).** These tools stay small by sharing a runtime you install
   once. Download the **Desktop Runtime** — not the SDK, and not the plain "Runtime" — for **Windows
   x64** from Microsoft:

   **https://dotnet.microsoft.com/download/dotnet/8.0**

   On that page find **.NET Desktop Runtime 8.x**, choose the **x64** installer, run it, and accept
   the defaults. You only need to do this once per computer. (You do *not* need Visual Studio or any
   developer tools.)

## Installing from the zip

You'll have received a file named something like `MyTool.zip`. Don't unzip it yourself — let Skyline
install it for you.

1. Open **Skyline**.
2. On the menu bar, choose **Tools ▸ External Tools…**. The **External Tools** dialog opens.
3. Click **Add ▸ From File…**.
4. Browse to the `.zip` you were given, select it, and click **Open**.
5. Skyline reads the tool's manifest and asks you to confirm the install. Click **OK** (or **Yes**).
6. The tool now shows up in the list. Click **OK** to close the dialog.

The tool now appears as its own item on the **Tools** menu.

> **Alternative:** you can also install with **Tools ▸ Tool Store ▸ Install from file**, then pick the
> same `.zip`. Either route installs the identical tool.

## Running the tool

1. Open (or keep open) the Skyline document you want to work with.
2. Choose **Tools ▸ *(your tool's name)***.
3. The tool launches and automatically connects to your **current document** — no configuration or
   file-picking needed. Follow the tool's own window from there.

## Updating or reinstalling

Installing a tool with the same name again simply **overwrites** the previous copy — that's how you
move to a newer version. Just repeat the *Installing from the zip* steps with the new `.zip`.

> ⚠️ **Close the running tool first.** If the tool is still open while you reinstall, Windows keeps
> its files locked, the new copy can only partly extract, and the tool may then **fail to start**.
> Always close the tool's window before reinstalling, then install the new zip.

## Removing the tool

1. Choose **Tools ▸ External Tools…**.
2. Select the tool in the list.
3. Click **Remove**, then **OK**.

## Troubleshooting

**The tool won't launch / the window flashes and vanishes.** By far the most common cause is a
**missing .NET 8.0 Desktop Runtime**. Install (or reinstall) the **x64 Desktop Runtime** from
**https://dotnet.microsoft.com/download/dotnet/8.0** and try again.

**It worked before but broke after a reinstall.** You probably reinstalled while the tool was still
open (see the warning above). Remove the tool, close any of its open windows, then install the `.zip`
again from scratch.

**Still stuck?** Note the exact error message and pass it to whoever gave you the tool — a message
about a missing file or assembly almost always points back to the .NET 8 Desktop Runtime prerequisite.
