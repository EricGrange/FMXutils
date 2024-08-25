unit FPointCloud;

interface

{$i fmxu.inc}

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.UIConsts, System.Math, System.Diagnostics,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Viewport3D,
  FMX.Controls.Presentation, FMX.StdCtrls, System.Math.Vectors, FMX.Controls3D,
  FMX.Objects3D, FMX.MaterialSources, FMX.Types3D, System.RTLConsts,
  FMX.Edit, FMX.EditBox, FMX.ComboTrackBar, FMX.ListBox,
  FMXU.D3DShaderCompiler, FMXU.PointCloud, FMXU.VertexBuffer, FMXU.Material.PointColor,
  FMXU.Viewport3D;

type
  TPointCloudForm = class(TForm)
    Viewport3D1: TViewport3D;
    Camera1: TCamera;
    DummyY: TDummy;
    Panel1: TPanel;
    CBShape: TComboBox;
    CTBPointSize: TComboTrackBar;
    Label1: TLabel;
    Label2: TLabel;
    DummyX: TDummy;
    TimerFPS: TTimer;
    Timer1: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
    procedure CBShapeChange(Sender: TObject);
    procedure CTBPointSizeChangeTracking(Sender: TObject);
    procedure TimerFPSTimer(Sender: TObject);
    procedure Viewport3D1Painting(Sender: TObject; Canvas: TCanvas;
      const ARect: TRectF);
    procedure FormMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
  private
    { Private declarations }
    FMouseDownPos : TPoint3D;
    FPointCloud : TPointCloud3D;
    FRenderCount : Integer;
    FRenderTicks : TStopwatch;
    FRunningFPS : Double;

    procedure OnApplicationIdle(Sender: TObject; var Done: Boolean);
  public
    { Public declarations }
  end;

var
  PointCloudForm: TPointCloudForm;

implementation

{$R *.fmx}

// ghetto loader for obj point clouds
// only looks at 'v' lines and assumes properties are x y z r g b
procedure LoadFromObj(const objFileName : String; cloud : TPointCloud3D);
var
   fmt : TFormatSettings;

   function ParseFloat(const s : String) : Double;
   begin
      if not TryStrToFloat(s, Result, fmt) then
         Assert(False, s);
   end;

begin
   fmt := FormatSettings;
   fmt.DecimalSeparator := '.';
   fmt.ThousandSeparator := ',';

   var objFile := TStringList.Create;
   var line := TStringList.Create('"', ' ');
   try
      // keep only 'v' lines
      objFile.LoadFromFile(objFileName);
      for var i := objFile.Count-1 downto 0 do begin
         var s := objFile[i];
         if (s = '') or (s[1] <> 'v') or (s[2] <> ' ') then
            objFile.Delete(i);
      end;

      cloud.Points.Length := objFile.Count;
      for var i := 0 to objFile.Count-1 do begin
         line.DelimitedText := objFile[i];
         cloud.Points.Vertices[i] := Point3D(
            ParseFloat(line[1]),
            -ParseFloat(line[2]),
            ParseFloat(line[3])
         );
         var c : TAlphaColorRec;
         c.R := Round(ParseFloat(line[4]) * 255);
         c.G := Round(ParseFloat(line[5]) * 255);
         c.B := Round(ParseFloat(line[6]) * 255);
         c.A := 1;
         cloud.Points.Color0[i] := c.Color;
      end;

      // auto-center and scale

      var bary := BufferBarycenter(cloud.Points);
      var factor := 20 / BufferAverageDistance(cloud.Points, bary);
      BufferOffsetAndScale(cloud.Points, -bary, factor);//.X, -bary.Y, -bary.Z), );
   finally
      line.Free;
      objFile.Free;
   end;
end;

procedure TPointCloudForm.FormCreate(Sender: TObject);
begin
   Application.OnIdle := OnApplicationIdle;

   FRenderTicks.Start;

   FPointCloud := TPointCloud3D.Create(Self);
   FPointCloud.Parent := Viewport3D1;

   LoadFromObj(
      '..\..\..\Data\Fish_SimpVal_1.obj',
      FPointCloud
   );

   CBShape.ItemIndex := 0;
   CTBPointSizeChangeTracking(Sender);
   CBShapeChange(Sender);
end;

procedure TPointCloudForm.FormMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
   MouseCapture;
   if Button = TMouseButton.mbLeft then begin
      FMouseDownPos.X := X;
      FMouseDownPos.Y := Y;
   end;
end;

procedure TPointCloudForm.FormMouseMove(Sender: TObject; Shift: TShiftState; X,
  Y: Single);
begin
   if Shift = [ssLeft ] then begin
      DummyY.RotationAngle.Y := DummyY.RotationAngle.Y + (X - FMouseDownPos.X) * 0.1;
      DummyX.RotationAngle.X := DummyX.RotationAngle.X - (Y - FMouseDownPos.Y) * 0.1;
      FMouseDownPos.X := X;
      FMouseDownPos.Y := Y;
   end;
end;

procedure TPointCloudForm.FormMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
   ReleaseCapture;
end;

procedure TPointCloudForm.FormMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
begin
   Camera1.AngleOfView := Camera1.AngleOfView * Power(1.15, WheelDelta / 120);
end;

procedure TPointCloudForm.CBShapeChange(Sender: TObject);
begin
   FPointCloud.PointShape := TPointColorShape(CBShape.ItemIndex);
end;

procedure TPointCloudForm.CTBPointSizeChangeTracking(Sender: TObject);
begin
   FPointCloud.PointSize := CTBPointSize.Value / 100;
end;

// OnApplicationIdle
//
procedure TPointCloudForm.OnApplicationIdle(Sender: TObject; var Done: Boolean);
begin
   Viewport3D1.Repaint;
   Done := False;
end;

procedure TPointCloudForm.TimerFPSTimer(Sender: TObject);
begin
   var count := FRenderCount;
   var elapsed := FRenderTicks.ElapsedMilliseconds;

   var fps : Double := 0;
   if count > 0 then
      fps := count / elapsed * 1000;

   FRenderTicks.Reset;
   FRenderTicks.Start;
   FRenderCount := 0;

   var paintFPS := 0.0;
   if Viewport3D1.LastPaintSeconds > 0 then
      paintFPS := 1 / Viewport3D1.LastPaintSeconds;
   FRunningFPS := FRunningFPS * 0.5  + fps * 0.5;

   Caption := Format(
      '%.1f ms paint (%.1f FPS) / %.1f actual FPS / %d points',
      [ Viewport3D1.LastPaintSeconds*1000, paintFPS, FRunningFPS, FPointCloud.Points.Length ]
   );
end;

procedure TPointCloudForm.Viewport3D1Painting(Sender: TObject; Canvas: TCanvas;
  const ARect: TRectF);
begin
   Inc(FRenderCount);
end;

end.
