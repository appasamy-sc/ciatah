function [success] = manageParallelWorkers(varargin)
	% Manages loading and stopping parallel processing workers.
	% Biafra Ahanonu
	% started: 2015.12.01
	
	[success] = ciapkg.io.manageParallelWorkers('passArgs', varargin);
end