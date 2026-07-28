function report=run_all_tests_4_5()
%RUN_ALL_TESTS_4_5 Standalone acceptance tests for the 4.5 submodel.
here=fileparts(mfilename('fullpath'));
moduleRoot=fileparts(here);
addpath(moduleRoot);
[~,report]=run_4_5_standalone_validation();
assert(all(report.passed),'4.5 standalone acceptance failed.');
end
