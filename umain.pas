{
 	Atmospheric Electricity Logger

	by Frank Hoogerbeets 2019-08-27 <frank@ditrianum.org>

	This program is free software; you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation; either version 2 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program; if not, write to the Free Software
	Foundation, Inc., 59 Temple Place, Suite 330, Boston,
	MA  02111-1307  USA
}

unit umain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Math, LazSerial, DateUtils, FileUtil, LazSysUtils;

const
  ArchiveFolder = 'archive';

type
  TReadDataThread = class(TThread)
  private
    procedure UpdateList;
  protected
    procedure Execute; override;
  public
    constructor Create(CreateSuspended: boolean);
  end;

  { TForm1 }

  TForm1 = class(TForm)
    btSetup: TButton;
    btStart: TButton;
    btStop: TButton;
    btClose: TButton;
    lbRecordingInfo: TLabel;
    LazSerial1: TLazSerial;
    ListBox1: TListBox;
    BackupTime: TTimer;
    procedure btCloseClick(Sender: TObject);
    procedure btSetupClick(Sender: TObject);
    procedure btStartClick(Sender: TObject);
    procedure btStopClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure BackupTimeTimer(Sender: TObject);
  private

  public
    procedure BackupData;
    procedure CheckArchiveTime(const aTime: TDateTime);
    procedure StartReadData;
    procedure StopReadData;
  end;

var
  Form1: TForm1;
  ReadDataThread: TReadDataThread;
  DataBuffer: string;
  csvFile: TextFile;
  FileName: string;
  CurrentMonth: word;
  LastMonth: word;
  LastTime: TDateTime;

implementation

function FileID(dt: TDateTime): string;
begin
  result := 'aelog-utc-'
    + FormatDateTime('YYYY-MM', dt)
    + '.csv'
end;

{$R *.lfm}

{ TForm1 }

procedure TForm1.CheckArchiveTime(const aTime: TDateTime);
{ Tries to archive the csvFile and create a new one (for the new month).
  If renaming/moving fails, an attempt is made to reopen the last csvFile
  to prevent loss of data. If this attempt fails the program will halt.
}
var
  aName: string;
  failed: boolean;
begin
  failed := false;

  If LastMonth > 0 then
    begin
      CurrentMonth := MonthOf(aTime);
      if CurrentMonth <> LastMonth then
        begin
          {
          try
            Flush(csvFile);
            CloseFile(csvFile);
          except
            failed := true;
          end;
          }
          if not failed then
            begin
              try

                aName := ArchiveFolder
                  + DirectorySeparator
                  + FileName;
                Rename(csvFile, aName);
                FileName := FileID(aTime);
                AssignFile(csvFile, FileName);
                Rewrite(csvFile);
              except
                ShowMessage('Error creating archive ' + aName);
                //failed := true;
              end;
              {
                Append to old file (if rename failed),
                or to new file (if rewrite succeeded).
                If rewrite failed, situation is hopeless...
              }
              try
                Append(csvFile);
              except
                // bad error
                ShowMessage('Could not recover from error while archiving data.');
                StopReadData;
              end;
            end;
          LastMonth := CurrentMonth;
          LastTime := aTime;
        end;
    end
  else
    LastTime := aTime;
    LastMonth := MonthOf(LastTime);
end;

procedure TForm1.BackupData;
begin
  CopyFile(FileName, FileName + '.backup', [cffOverwriteFile]);
end;

procedure TForm1.StartReadData;
begin
  {
  try
    Append(csvFile);
  except
    ShowMessage('Error opening ' + FileName);
    exit;
  end;
  }

  LazSerial1.Open;
  LazSerial1.Active := true;
  LazSerial1.SynSer.Flush;

  lbRecordingInfo.Caption := 'Device recording: '+ LazSerial1.Device;

  ReadDataThread := TReadDataThread.Create(false);

  btSetup.Enabled := false;
  btStart.Enabled := false;
  btStop.Enabled := true;
end;

procedure TForm1.StopReadData;
begin
  // bail out if thread is nil (see FormClose)
  if ReadDataThread = nil then
    exit;

  lbRecordingInfo.Caption := 'Device stopping: ' + LazSerial1.Device;

  ReadDataThread.Terminate;
  // ReadDataThread.WaitFor;
  Sleep(1000);
  ReadDataThread := nil;

  LazSerial1.Close;
  LazSerial1.Active := false;

  //try
  //  CloseFile(csvFile);
  //finally
    lbRecordingInfo.Caption := 'Selected device: ' + LazSerial1.Device;
  //end;

  btSetup.Enabled := true;
  btStart.Enabled := true;
  btStop.Enabled := false;
end;

procedure TForm1.btSetupClick(Sender: TObject);
begin
  LazSerial1.ShowSetupDialog;
  lbRecordingInfo.Caption := 'Selected device: '+ LazSerial1.Device;
end;

procedure TForm1.btCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TForm1.btStartClick(Sender: TObject);
begin
  StartReadData;
end;

procedure TForm1.btStopClick(Sender: TObject);
begin
  StopReadData;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  StopReadData;
  LazSerial1.Free;
  CloseAction := caFree;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  try
    if not DirectoryExists(ArchiveFolder) then
      CreateDir(ArchiveFolder);
  except
    ShowMessage('AeLog could not create the archive folder.');
    Close;
  end;

  FileName := FileID(NowUTC);

  AssignFile(csvFile, FileName);

  if not FileExists(FileName) then
    try
      Rewrite(csvFile);
    except
      ShowMessage('AeLog could not open the log file.');
      Close;
    end;

  DefaultFormatSettings.DecimalSeparator := '.';
  Application.UpdateFormatSettings := false;

  LazSerial1.BaudRate := br__9600;
  LazSerial1.DataBits := db8bits;

  {$if defined(windows)}
    LazSerial1.Device:= 'COM1';
  {$else}
    LazSerial1.Device:= '/dev/ttyACM0';
  {$ifend}

  lbRecordingInfo.Caption := 'Selected device: ' + LazSerial1.Device;

  BackupTime.Interval := 600000; // 10 minutes
  BackupTime.Enabled := true;

  btStop.Enabled := false;
  btStart.Enabled := true;

  LastTime := 0;
  LastMonth := 0;
end;

procedure TForm1.BackupTimeTimer(Sender: TObject);
begin
  BackupData;
end;

{ thread }

constructor TReadDataThread.Create(CreateSuspended: boolean);
begin
  inherited Create(CreateSuspended);
  Priority := tpHighest;
  FreeOnTerminate := true;
end;

procedure TReadDataThread.UpdateList;
begin
  // only keep last 100 entries
  if Form1.ListBox1.Items.Count > 99 then
    Form1.ListBox1.Items.Delete(0);

  Form1.ListBox1.Items.Add(DataBuffer);
  Form1.ListBox1.ItemIndex := Form1.ListBox1.Items.Count - 1;
end;

procedure TReadDataThread.Execute;
const
  size = 128;
var
  i: integer;
  value: extended;
  volts: double;
  aTime: TDateTime;
begin
  while not Terminated do
    begin
      value := 0;
      volts := 0;

      for i := 1 to size do
        begin
          DataBuffer := Form1.LazSerial1.SynSer.RecvString(1000);
          if (not TextToFloat(pchar(DataBuffer), value)) or Terminated then
            begin
             volts := Nan;
             break;
            end;
          volts := volts + value;
          {$if defined(windows)}
            Form1.LazSerial1.SynSer.SetBreak(200);
          {$ifend}
        end;

      aTime := NowUTC;
      value := volts / size;

      DataBuffer := FormatDateTime('YYYY-MM-DD hh:nn:ss', aTime)
        + ','
        + FloatToStr(value);

      Form1.CheckArchiveTime(aTime);
      try
        Append(csvFile);
        writeln(csvFile, DataBuffer);
        Flush(csvFile);
        Close(csvFile);
      except
        ShowMessage('AeLog could not access log file.');
        break;
      end;

      Synchronize(@UpdateList);
    end;
end;

end.

