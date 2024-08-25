program PointCloud;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Types,
  FPointCloud in 'FPointCloud.pas' {PointCloudForm};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TPointCloudForm, PointCloudForm);
  Application.Run;
end.
