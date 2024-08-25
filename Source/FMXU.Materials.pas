{**********************************************************************}
{                                                                      }
{    "The contents of this file are subject to the Mozilla Public      }
{    License Version 2.0 (the "License"); you may not use this         }
{    file except in compliance with the License. You may obtain        }
{    a copy of the License at http://www.mozilla.org/MPL/              }
{                                                                      }
{    Software distributed under the License is distributed on an       }
{    "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express       }
{    or implied. See the License for the specific language             }
{    governing rights and limitations under the License.               }
{                                                                      }
{    Material & shaders utilities                                      }
{                                                                      }
{**********************************************************************}
unit FMXU.Materials;

{$i fmxu.inc}

interface

uses FMX.Types3D;

//: Guess TContextShaderArch from TContext3D classname
function ContextShaderArchitecture : TContextShaderArch;

// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------
implementation
// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------

var
   vLastContext3DClass : TClass;
   vLastContextShaderArch : TContextShaderArch;

// PrepareContextShaderArchitecture
//
procedure PrepareContextShaderArchitecture;
begin
   vLastContext3DClass := TContextManager.DefaultContextClass;
   vLastContextShaderArch := TContextShaderArch.Undefined;

   var name := vLastContext3DClass.ClassName;
   if Pos('DX9', name) > 0 then begin
      if Pos('DX9', name) > 0 then
         vLastContextShaderArch := TContextShaderArch.DX9
      else if Pos('DX10', name) > 0 then
         vLastContextShaderArch := TContextShaderArch.DX10
      else if Pos('DX11', name) > 0 then
         vLastContextShaderArch := TContextShaderArch.DX11
   end else if Pos('Metal', name) > 0 then
      vLastContextShaderArch := TContextShaderArch.Metal
   else if Pos('Android', name) > 0 then
      vLastContextShaderArch := TContextShaderArch.Android;

   if vLastContextShaderArch = TContextShaderArch.Undefined then begin
      raise EContext3DException.CreateFmt(
         'ContextShaderArchitecture for "%s" not implemented yet', [ name ]
      );
   end;
end;

// ContextShaderArchitecture
//
function ContextShaderArchitecture : TContextShaderArch;
begin
   if TContextManager.DefaultContextClass <> vLastContext3DClass then
      PrepareContextShaderArchitecture;
   Result := vLastContextShaderArch;
end;

end.
