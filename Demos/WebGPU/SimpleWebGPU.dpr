program SimpleWebGPU;

uses
  System.StartUpCopy,
  FMX.Forms,
  FSimpleWebGPU in 'FSimpleWebGPU.pas' {Form27},
  FMXU.Context.WebGPU,
  FMXU.Context.DX11,
  FMXU.WebGPU.Materials in '..\..\Source\FMXU.WebGPU.Materials.pas';

{$R *.res}

begin
   RegisterWebGPUContext;       // 16 ms = 60 FPS VSync
//   RegisterDX11ContextU;      // 0.3 ms

   Application.Initialize;
   Application.CreateForm(TForm27, Form27);
  Application.Run;
end.
