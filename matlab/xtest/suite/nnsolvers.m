classdef nnsolvers < nntest
  properties (TestParameter)
    networkType = {'simplenn', 'dagnn'}
    solver = {'sgd', 'adagrad', 'adadelta'}
  end
  properties
    imdb
    init_w
    init_b
  end

  methods (TestClassSetup)
    function data(test)
      % synthetic data, 2 classes of gaussian samples with different means
      test.range = 2 ;  % set standard deviation of test.randn()
      sz = [15, 10, 5] ;  % input size
      x1 = test.randn([sz, 100]) ;  % place mean at the origin
      x2 = bsxfun(@plus, test.randn(sz), test.randn([sz, 100])) ;  % place mean randomly
      
      test.imdb.x = cat(4, x1, x2) ;
      test.imdb.y = [test.ones(100, 1); 2 * test.ones(100, 1)] ;
      
      test.init_w = 1e-3 * test.randn([sz, 2]) ;  % initial parameters
      test.init_b = test.zeros([2, 1]) ;
    end
  end

  methods (Test)
    function basic(test, networkType, solver)
      clear mex ; % will reset GPU, remove MCN to avoid crashing
                  % MATLAB on exit (BLAS issues?)
      if strcmp(test.dataType, 'double'), return ; end

      % a simple logistic regression network
      net.layers = {struct('type','conv', 'weights',{{test.init_w, test.init_b}}), ...
                    struct('type','softmaxloss')} ;
      
      switch test.currentDevice
        case 'cpu', gpus = [];
        case 'gpu', gpus = 1;
      end

      switch networkType
        case 'simplenn',
          trainfn = @cnn_train ;
          getBatch = @(imdb, batch) deal(imdb.x(:,:,:,batch), imdb.y(batch)) ;
          
        case 'dagnn',
          trainfn = @cnn_train_dag ;
          
          if isempty(gpus)
            getBatch = @(imdb, batch) ...
                {'input',imdb.x(:,:,:,batch), 'label',imdb.y(batch)} ;
          else
            getBatch = @(imdb, batch) ...
                {'input',gpuArray(imdb.x(:,:,:,batch)), 'label',imdb.y(batch)} ;
          end
          
          net = dagnn.DagNN.fromSimpleNN(net, 'canonicalNames', true) ;
          net.addLayer('error', dagnn.Loss('loss', 'classerror'), ...
                      {'prediction','label'}, 'error') ;
      end

      % train 1 epoch with small batches and check convergence
      [~, info] = trainfn(net, test.imdb, getBatch, ...
        'train', 1:numel(test.imdb.y), 'val', 1, ...
        'solver',solver, 'batchSize', 10, 'numEpochs',1, 'continue', false, ...
        'gpus', gpus, 'plotStatistics', false) ;

      test.verifyLessThan(info.train.error(1), 0.3);
      test.verifyLessThan(info.train.objective, 0.45);
    end
  end
end