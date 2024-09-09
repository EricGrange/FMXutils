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
{    This unit holds color-related utilities                           }
{                                                                      }
{**********************************************************************}
unit FMXU.Colors;

interface

uses System.UITypes;

function ColorComposeAlpha(const color : TAlphaColor; const aOpacity : Single) : TAlphaColor;

// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------
implementation
// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------

// ColorComposeAlpha
//
function ColorComposeAlpha(const color : TAlphaColor; const aOpacity : Single) : TAlphaColor;
begin
   Result := color;
   if aOpacity < 1 then
      TAlphaColorRec(Result).A := Trunc(TAlphaColorRec(color).A * aOpacity);
end;

end.
