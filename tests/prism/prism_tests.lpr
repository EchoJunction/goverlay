program prism_tests;
{$mode objfpc}{$H+}
uses fpcunit, testregistry, plaintestreport, prism_test_cases, prism_settings_test_cases, prism_document_test_cases, prism_env_test_cases;
var Results: TTestResult; Writer: TPlainResultsWriter; Failed: Boolean;
begin
  Results := TTestResult.Create;
  Writer := TPlainResultsWriter.Create(nil);
  try
    GetTestRegistry.Run(Results);
    Writer.WriteHeader;
    Writer.WriteResult(Results);
    Failed := (Results.NumberOfErrors <> 0) or (Results.NumberOfFailures <> 0);
  finally
    Writer.Free; Results.Free;
  end;
  if Failed then Halt(1);
end.
