program SimpleWebGPUViewport;

uses
  System.StartUpCopy,
  FMX.Forms,
  FSimpleViewport in 'FSimpleViewport.pas' {Form27}
  ,FMXU.Context.WebGPU
  ,FMXU.Context.DX11
  ;

{$R *.res}

begin
   RegisterWebGPUContext;       // 2.4 ms  with copy to texture overhead
//   RegisterDX11ContextU;          // 1.4 ms

   Application.Initialize;
   Application.CreateForm(TForm27, Form27);
   Application.Run;
end.
