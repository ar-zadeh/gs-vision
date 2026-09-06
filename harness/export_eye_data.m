% Export the downloaded MATLAB table without modifying its source archive.
root = fileparts(fileparts(mfilename('fullpath')));
source = fullfile(root, 'data', 'human', 'wu_wolfe2022', 'Exp1Data.mat');
destination = fullfile(root, 'data', 'model', 'repair_20260905');
loaded = load(source, 'Exp1Data');
data = loaded.Exp1Data;
assert(istable(data), 'Expected a MATLAB table');
writetable(data, fullfile(destination, 'eye_exp1.csv'));
metadata.source = source;
metadata.rows = height(data);
metadata.columns = data.Properties.VariableNames;
metadata.units = data.Properties.VariableUnits;
metadata.descriptions = data.Properties.VariableDescriptions;
f = fopen(fullfile(destination, 'eye_exp1_metadata.json'), 'w');
fprintf(f, '%s', jsonencode(metadata));
fclose(f);
disp(data(1:min(3,height(data)),:));
