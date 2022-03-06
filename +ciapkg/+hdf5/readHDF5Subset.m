function [dataSubset fid] = readHDF5Subset(inputFilePath, offset, block, varargin)
	% Gets a subset of data from an HDF5 file.
	% Biafra Ahanonu
	% started: 2013.11.10
	% based on code from MathWorks; for details, see http://www.mathworks.com/help/matlab/ref/h5d.read.html
	% inputs
		%
		% offset = cell array of [xOffset yOffset frameOffset]
		% block = cell array of [xDim yDim frames], xDim and yDim should be the same size across all cell arrays, note, the "frames" dimension SHOULD NOT have overlapping frames across cell arrays
	% options
		% datasetName = hierarchy where data is stored in HDF5 file
	% changelog
		% 2013.11.30 [17:59:14]
		% 2014.01.15 [09:59:53] cleaned up code, removed unnecessary options
		% 2017.01.18 [15:01:15] added option to deal with 3D data in 4D format with singleton 4th dimension
		% 2018.09.28 - changed so can read from multiple non-contiguous	slabs of data at the same time
		% 2019.02.13 [14:52:33] - Updated to support not closing file ID and importing an existing file ID to improve speed.
		% 2019.02.13 - Updated to support when user ask for multiple offsets at the same location in file.
		% 2019.02.13 [17:57:55] - Improved duplicate frame support, finds differences in frames, loads all unique as a single slab, then loads remaining and re-organizes to be in correct order.
		% 2019.05.03 [15:42:08] - Additional 4D support in cases where a 3D offset/block request is made.
		% 2019.10.10 [12:52:54] - Add correction for frame order. Select hyperslab in HDF5 makes blocks in sorted order, so after reading the explicit offset ordering is not the original unsorted order.
		% 2021.02.15 [12:02:36] - Updated support for files with datasets that contain 2D matrices.
		% 2021.08.08 [19:30:20] - Updated to handle CIAtah v4.0 switch to all functions inside ciapkg package.
		% 2022.01.27 [13:20:04] - Fix display of information on error.
	% TODO
		% DONE: Make support for duplicate frames more robust so minimize the number of file reads.

	import ciapkg.api.* % import CIAtah functions in ciapkg package API.

	%========================
	% old way of saving, only temporary until full switch
	options.datasetName = '/1';
	% Binary: 1 = display output info, 0 = don't display any output info
	options.displayInfo = 1;
	%
	options.keepFileOpen = 0;
	%
	options.hdf5Fid = [];
	% 1 = error run, exit on error to prevent recursive loop
	options.errorRun = 0;
	% get options
	options = getOptions(options,varargin);
	% unpack options into current workspace
	% fn=fieldnames(options);
	% for i=1:length(fn)
	%     eval([fn{i} '=options.' fn{i} ';']);
	% end
	%========================
	% get file info
	% hinfo = hdf5info(inputFilePath);
	% hReadInfo = hinfo.GroupHierarchy.Datasets(1);
	% xDim = hReadInfo.Dims(1);
	% yDim = hReadInfo.Dims(2);
	offsetRaw = offset;
	blockRaw = block;
	if iscell(offset)~=1
	   offsetTmp = {};
	   offsetTmp{1} = offset;
	   offset = offsetTmp;
	end
	if iscell(block)~=1
	   blockTmp = {};
	   blockTmp{1} = block;
	   block = blockTmp;
	end

	nSlabs = length(offset);

	% display file information for reference
	if options.displayInfo==1
		for sNo = 1:nSlabs
			% display(['loading chunk | offset: ' num2str(offset{sNo}) ' | block: ' num2str(block{sNo}) 10]);
			disp(['loading chunk | offset: ' num2str(offset{sNo}) ' | block: ' num2str(block{sNo})]);
		end
	end

	% open fid to hdf5 dataset
	plist = 'H5P_DEFAULT';
	if isempty(options.hdf5Fid)
		fid = H5F.open(inputFilePath);
	else
		fid = options.hdf5Fid;
	end
	% options.hdf5Fid
	% fid
	dset_id = H5D.open(fid,options.datasetName);
	dims = fliplr(block{1});%[xDim yDim 1]
	tmpVar = sum(cat(1,block{:}),1);
	if length(block{1})==2
		% Do nothing.
	elseif length(block{1})==3
		dims(1) = tmpVar(3);
	elseif length(block{1})==4
		dims(1) = tmpVar(4);
	else
		disp('Dimensions not supported')
		return;
	end
	mem_space_id = H5S.create_simple(length(dims),dims,dims);
	file_space_id = H5D.get_space(dset_id);

	try
		offSetAll = cat(1,offset{:});
		offSetUnique = unique(offSetAll,'stable','rows');
        % offSetUnique
        % offSetAll
		% Check if there are duplicates (read in each frame-by-frame if so) else continue as normal.
		% if size(offSetAll,1)==size(offSetUnique,1)
        if size(offSetAll)==size(offSetUnique)
            frameCorrectOrder = [];
			for sNo = 1:nSlabs
				% offset and size of the block to get, flip dimensions so in format that H5S wants
				offsetFlip = fliplr(offset{sNo});
				blockFlip = fliplr(block{sNo});

				% select the hyperslab
				% H5S.select_hyperslab(file_space_id,'H5S_SELECT_SET',offsetFlip,[],[],blockFlip);

				% select the hyperslab
				if sNo==1
					H5S.select_hyperslab(file_space_id,'H5S_SELECT_SET',offsetFlip,[],[],blockFlip);
				else
					H5S.select_hyperslab(file_space_id,'H5S_SELECT_OR',offsetFlip,[],[],blockFlip);
                end
                frameCorrectOrder(end+1) = offsetFlip(1);
				%output = H5S.select_valid(file_space_id)
				%[start,finish] = H5S.get_select_bounds(file_space_id)
				% select the data subset
            end
            % [start,finish] = H5S.get_select_bounds(file_space_id)
            % blocklist = H5S.get_select_hyper_blocklist(file_space_id,0,H5S.get_select_hyper_nblocks(file_space_id))
			dataSubset = H5D.read(dset_id,'H5ML_DEFAULT',mem_space_id,file_space_id,plist);
            [~,frameCorrectOrder] = sort(frameCorrectOrder,'ascend');
            dataSubset(:,:,frameCorrectOrder) = dataSubset(:,:,1:length(frameCorrectOrder));
            % playMovie(dataSubset)
        else
			if options.displayInfo==1
				disp('Input offsets not unique! Using backup method.')
			end
			% dataSubset = {};
			offSetAll = cat(1,offset{:});
			blockAll = cat(1,block{:});

			[offSetUniqueTmp,keptIdx,uniqueGroupsIdx] = unique(offSetAll,'stable','rows');
			offSetUnique = offset(keptIdx);
			blockUnique = block(keptIdx);
			% cat(1,offSetUnique{:})

			dims = fliplr(blockUnique{1});%[xDim yDim 1]
			tmpVar = sum(cat(1,blockUnique{:}),1);
			dims(1) = tmpVar(3);
			mem_space_id = H5S.create_simple(length(dims),dims,dims);
			file_space_id = H5D.get_space(dset_id);

			nSlabsTmp = length(offSetUnique);

			frameCorrectOrder = [];
			for sNoTmp = 1:nSlabsTmp
				% offset and size of the block to get, flip dimensions so in format that H5S wants
				offsetFlip = fliplr(offSetUnique{sNoTmp});
				blockFlip = fliplr(blockUnique{sNoTmp});

				% select the hyperslab
				% H5S.select_hyperslab(file_space_id,'H5S_SELECT_SET',offsetFlip,[],[],blockFlip);

				% select the hyperslab
				if sNoTmp==1
					H5S.select_hyperslab(file_space_id,'H5S_SELECT_SET',offsetFlip,[],[],blockFlip);
				else
					H5S.select_hyperslab(file_space_id,'H5S_SELECT_OR',offsetFlip,[],[],blockFlip);
				end
                frameCorrectOrder(end+1) = offsetFlip(1);
				%output = H5S.select_valid(file_space_id)
				%[start,finish] = H5S.get_select_bounds(file_space_id)
				% select the data subset
				% [dataSubset{sNo}] = readHDF5Subset(inputFilePath, offset{sNoTmp}, block{sNoTmp},'options',options);
			end
			dataSubset = H5D.read(dset_id,'H5ML_DEFAULT',mem_space_id,file_space_id,plist);
			% dataSubset = cat(3,dataSubset{:});
			[~,frameCorrectOrder] = sort(frameCorrectOrder,'ascend');
			dataSubset(:,:,frameCorrectOrder) = dataSubset(:,:,1:length(frameCorrectOrder));

			idList = 1:nSlabs;
			remainIdx = idList(setdiff(idList,keptIdx,'stable'));
			offSetRemain = offset(remainIdx);
			blockRemain = block(remainIdx);
			nSlabsTmp = length(offSetRemain);
			dataSubsetRemain = {};
			for sNoTmp = 1:nSlabsTmp
				% offsetFlip = fliplr(offSetUnique{sNoTmp});
				% blockFlip = fliplr(blockUnique{sNoTmp});
				[dataSubsetRemain{sNoTmp}] = readHDF5Subset(inputFilePath, offSetRemain{sNoTmp}, blockRemain{sNoTmp},'options',options);
			end
			dataSubsetRemain = cat(3,dataSubsetRemain{:});

			dataSubset = cat(3,dataSubset,dataSubsetRemain);
			[newIdx,oldIdx] = sort([keptIdx(:);remainIdx(:)]');
			% rearrangeIdx =
			dataSubset(:,:,newIdx) = dataSubset(:,:,oldIdx);
		end
	catch err
		display(repmat('=',1,7))
        display(repmat('@',1,7))
		disp(getReport(err,'extended','hyperlinks','on'));
		display(repmat('@',1,7))

		% offsetError = cat(1,offset{:});
		% blockError = cat(1,block{:});

        offsetError = [offset{:}];
		blockError = [block{:}];

		% size(offset);
		% size(block);
		disp(['offsetError: ' num2str(offsetError)]);
		disp(['blockError: ' num2str(blockError)]);
		disp(['offset: ' num2str(size(offset))]);
		disp(['block: ' num2str(size(block))]);

		if options.errorRun==1
			return;
		end

		try
			if options.displayInfo==1
				display('Block contains extra dimension');
			end
			% offset and size of the block to get, flip dimensions so in format that H5S wants
			offsetTmp = offset;
			blockTmp = block;
			for kk = 1:length(offsetTmp)
				offsetTmp{kk}(4) = 0;
				blockTmp{kk}(4) = 1;
			end

			options.errorRun = 1;

			[dataSubset] = readHDF5Subset(inputFilePath, offsetTmp, blockTmp,'options',options);

			% % select the hyperslab
			% H5S.select_hyperslab(file_space_id,'H5S_SELECT_SET',offsetFlip,[],[],blockFlip);
			% % select the data subset
			% dataSubset = H5D.read(dset_id,'H5ML_DEFAULT',mem_space_id,file_space_id,plist);
		catch err
			display(repmat('@',1,7))
			disp(getReport(err,'extended','hyperlinks','on'));
			display(repmat('@',1,7))
		end
	end

	% close IDs
	H5S.close(file_space_id);
	H5D.close(dset_id);
	if options.keepFileOpen==1
	else
		H5F.close(fid);
	end

	% output file size
	j = whos('dataSubset');j.bytes=j.bytes*9.53674e-7;
	if options.displayInfo==1
		disp(['movie size: ' num2str(j.bytes) 'Mb | ' num2str(j.size) ' | ' j.class])
	end
end