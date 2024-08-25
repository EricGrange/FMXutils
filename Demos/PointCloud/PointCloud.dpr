program PointCloud;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Types,
  FMX.Context.DX11,
  FPointCloud in 'FPointCloud.pas' {PointCloudForm},
  FMXU.Viewport3D in '..\..\Source\FMXU.Viewport3D.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TPointCloudForm, PointCloudForm);
  Application.Run;
end.
