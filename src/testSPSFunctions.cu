#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "hostSkel.cu.h"
//#include "sps.cu.h"

// R seems to be max value of the elements of the array
// void initArray(int32_t* inp_arr, const uint32_t N, const int R) {
//     const uint32_t M = 2*R+1;
//     for(uint32_t i=0; i<N; i++) {
//         inp_arr[i] = (rand() % M) - R;
//     }
// }

/**
 * Measure a more-realistic optimal bandwidth by a simple, memcpy-like kernel
 * B - desired CUDA block size ( <= 1024, multiple of 32)
 * N - length of the input array
 * d_in  - device input  of length N
 * d_out - device result of length N
 */ 
// int bandwidthMemcpy(const uint32_t B, const size_t N, int* d_in, int* d_out) {
//     // dry run to exercise the d_out allocation!
//     const uint32_t num_blocks = (N + B - 1) / B;
//     naiveMemcpy<<< num_blocks, B >>>(d_out, d_in, N);

//     double gigaBytesPerSec;
//     unsigned long int elapsed;
//     struct timeval t_start, t_end, t_diff;

//     { // timing the GPU implementations
//         gettimeofday(&t_start, NULL); 

//         for(int i=0; i<RUNS_GPU; i++) {
//             naiveMemcpy<<< num_blocks, B >>>(d_out, d_in, N);
//         }
//         cudaDeviceSynchronize();

//         gettimeofday(&t_end, NULL);
//         timeval_subtract(&t_diff, &t_end, &t_start);
//         elapsed = (t_diff.tv_sec*1e6+t_diff.tv_usec) / RUNS_GPU;
//         gigaBytesPerSec = 2 * N * sizeof(int) * 1.0e-3f / elapsed;
//         printf("Naive Memcpy GPU Kernel runs in: %lu microsecs, GB/sec: %.2f\n\n\n"
//               , elapsed, gigaBytesPerSec);
//     }
 
//     gpuAssert( cudaPeekAtLastError() );
//     return 0;
// }

/**
 * Tests our SPS implementation
 * B - desired CUDA block size ( <= 1024, multiple of 32)
 * N - length of the input array
 * h_in  - host input  of length N
 * d_in  - device input  of length N
 * d_out - device result of length N
 */

// int spsTests(const uint32_t B, const size_t N, int32_t* h_in, int32_t* d_in, int32_t* d_out) {
int spsTests(const size_t N, int32_t* h_in, int32_t* d_in, int32_t* d_out) {
    const size_t mem_size = N * sizeof(int32_t);
    int32_t* h_out = (int32_t*)malloc(mem_size);
    uint32_t num_blocks = (N+B*Q-1)/(B*Q) + 1;  // We add 1 to be our auxiliary block.
		size_t f_array_size = num_blocks - 1;
    int32_t* IDAddr;
    uint32_t* flagArr;
    int32_t* aggrArr;
    int32_t* prefixArr;
    cudaMalloc((void**)&IDAddr, sizeof(int32_t));
    cudaMemset(IDAddr, -1, sizeof(int32_t));
    cudaMalloc((void**)&flagArr, f_array_size * sizeof(uint32_t));
    cudaMemset(flagArr, X, f_array_size * sizeof(uint32_t));
    cudaMalloc((void**)&aggrArr, f_array_size * sizeof(int32_t));
    cudaMemset(aggrArr, 0, f_array_size * sizeof(int32_t));
    cudaMalloc((void**)&prefixArr, f_array_size * sizeof(uint32_t));
    cudaMemset(prefixArr, 0, f_array_size * sizeof(uint32_t));

		{
			SPSFunctionTest2<<<num_blocks, B>>>(d_in, d_out, N, IDAddr, flagArr, aggrArr, prefixArr);
		}
		cudaMemcpy(h_out, d_out, mem_size, cudaMemcpyDeviceToHost);

		int32_t h_ref[16] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};

		printf("N: %d\n", N);
		printf("memsize: %d\n", mem_size);
		printf("num_blocks: %d\n", num_blocks);
		for (uint32_t i = 0; i < 16; i++) {
			printf("Single Pass Scan at index %d, dev-val: %d\n", i, h_out[i]);
		}

		printf("\n");

		for (uint32_t i = 0; i < N; i++) {
			if (h_out[i] != h_ref[i]) {
				printf("!!!INVALID!!!: Single Pass Scan at index %d, dev-val: %d, host-val: %d\n"
				, i, h_out[i], h_ref[i]);
				exit(1);
			}
		}
		printf("Single pass scan: VALID result!\n\n");

    free(h_out);
    cudaFree(IDAddr);
    cudaFree(flagArr);
    cudaFree(aggrArr);
    cudaFree(prefixArr);

    return 0;
}

int singlePassScan( // const uint32_t     B     // desired CUDA block size ( <= 1024, multiple of 32)
              const size_t       N     // length of the input array
            , int32_t* h_in            // host input    of size: N * sizeof(int)
            , int32_t* d_in            // device input  of size: N * sizeof(ElTp)
            , int32_t* d_out           // device result of size: N * sizeof(int)
            ){
    const size_t mem_size = N * sizeof(int32_t);
    int32_t* h_out = (int32_t*)malloc(mem_size);
    int32_t* h_ref = (int32_t*)malloc(mem_size);
    uint32_t num_blocks = (N+B*Q-1)/(B*Q) + 1;
    int32_t* IDAddr;
    uint32_t* flagArr;
    int32_t* aggrArr;
    int32_t* prefixArr;
    cudaMalloc((void**)&IDAddr, sizeof(int32_t));
    cudaMemset(IDAddr, -1, sizeof(int32_t));
    cudaMalloc((void**)&flagArr, sizeof(uint32_t));
    cudaMemset(flagArr, X, sizeof(uint32_t));
    cudaMalloc((void**)&aggrArr, sizeof(int32_t));
    cudaMemset(aggrArr, 0, sizeof(int32_t));
    cudaMalloc((void**)&prefixArr, sizeof(uint32_t));
    cudaMemset(prefixArr, 0, sizeof(uint32_t));

    unsigned long int elapsed;
    struct timeval t_start, t_end, t_diff;
    // Need to reset the dynID and flag arr each time we call the kernel
    // Before we can start to run it multiple times and get a benchmark.
    SinglePassScanKernel1<<< num_blocks, B, B*(Q+1)>>>(d_in, d_out, N, IDAddr, flagArr, aggrArr, prefixArr);
    cudaDeviceSynchronize();
    gpuAssert( cudaPeekAtLastError() );
    // For now we run it once on GPU and test that it is valid.
    // The CPU we might as well just add the benchmark
    { // sequential computation
        gettimeofday(&t_start, NULL);
        for(int i=0; i<RUNS_CPU; i++) {
            int acc = 0;
            for(uint32_t i=0; i<N; i++) {
                acc += h_in[i];
                h_ref[i] = acc;
            }
        }
        gettimeofday(&t_end, NULL);
        timeval_subtract(&t_diff, &t_end, &t_start);
        elapsed = (t_diff.tv_sec*1e6+t_diff.tv_usec) / RUNS_CPU;
        double gigaBytesPerSec = N * (sizeof(int) + sizeof(int)) * 1.0e-3f / elapsed;
        printf("Scan Inclusive AddI32 CPU Sequential runs in: %lu microsecs, GB/sec: %.2f\n"
              , elapsed, gigaBytesPerSec);
    }

    { // Validation
        cudaMemcpy(h_out, d_out, mem_size, cudaMemcpyDeviceToHost);
        for(uint32_t i = 0; i<N; i++) {
            if(h_out[i] != h_ref[i]) {
                printf("!!!INVALID!!!: Single Pass Scan at index %d, dev-val: %d, host-val: %d\n"
                      , i, h_out[i], h_ref[i]);
                exit(1);
            }
        }
        printf("Single pass scan: VALID result!\n\n");
    }
    free(h_out);
    cudaFree(IDAddr);
    cudaFree(flagArr);
    cudaFree(aggrArr);
    cudaFree(prefixArr);
    
    return 0;
}

int scanIncAddI32( // const uint32_t B     // desired CUDA block size ( <= 1024, multiple of 32)
                   const size_t   N     // length of the input array
                 , int* h_in            // host input    of size: N * sizeof(int)
                 , int* d_in            // device input  of size: N * sizeof(ElTp)
                 , int* d_out           // device result of size: N * sizeof(int)
) {
    const size_t mem_size = N * sizeof(int);
    int* d_tmp;
    int* h_out = (int*)malloc(mem_size);
    int* h_ref = (int*)malloc(mem_size);
    cudaMalloc((void**)&d_tmp, MAX_BLOCK*sizeof(int));
    cudaMemset(d_out, 0, N*sizeof(int));

    // dry run to exercise d_tmp allocation
    // scanInc< Add<int> > ( B, N, d_out, d_in, d_tmp );

    // time the GPU computation
    unsigned long int elapsed;
    struct timeval t_start, t_end, t_diff;
    gettimeofday(&t_start, NULL); 

    for(int i=0; i<RUNS_GPU; i++) {
        // scanInc< Add<int> > ( B, N, d_out, d_in, d_tmp );
    }
    cudaDeviceSynchronize();

    gettimeofday(&t_end, NULL);
    timeval_subtract(&t_diff, &t_end, &t_start);
    elapsed = (t_diff.tv_sec*1e6+t_diff.tv_usec) / RUNS_GPU;
    double gigaBytesPerSec = N  * (2*sizeof(int) + sizeof(int)) * 1.0e-3f / elapsed;
    printf("Scan Inclusive AddI32 GPU Kernel runs in: %lu microsecs, GB/sec: %.2f\n"
          , elapsed, gigaBytesPerSec);

    gpuAssert( cudaPeekAtLastError() );

    { // sequential computation
        gettimeofday(&t_start, NULL);
        for(int i=0; i<RUNS_CPU; i++) {
            int acc = 0;
            for(uint32_t i=0; i<N; i++) {
                acc += h_in[i];
                h_ref[i] = acc;
            }
        }
        gettimeofday(&t_end, NULL);
        timeval_subtract(&t_diff, &t_end, &t_start);
        elapsed = (t_diff.tv_sec*1e6+t_diff.tv_usec) / RUNS_CPU;
        double gigaBytesPerSec = N * (sizeof(int) + sizeof(int)) * 1.0e-3f / elapsed;
        printf("Scan Inclusive AddI32 CPU Sequential runs in: %lu microsecs, GB/sec: %.2f\n"
              , elapsed, gigaBytesPerSec);
    }

    { // Validation
        cudaMemcpy(h_out, d_out, mem_size, cudaMemcpyDeviceToHost);
        for(uint32_t i = 0; i<N; i++) {
            if(h_out[i] != h_ref[i]) {
                printf("!!!INVALID!!!: Scan Inclusive AddI32 at index %d, dev-val: %d, host-val: %d\n"
                      , i, h_out[i], h_ref[i]);
                exit(1);
            }
        }
        printf("Scan Inclusive AddI32: VALID result!\n\n");
    }

    free(h_out);
    free(h_ref);
    cudaFree(d_tmp);
    
    return 0;
}


int main (int argc, char * argv[]) {
    if (argc != 2) {
        // printf("Usage: %s <array-length> <block-size> <Q-size>\n", argv[0]);
        printf("Usage: %s <array-length>\n", argv[0]);
        exit(1);
    }

    initHwd();

    const uint32_t N = atoi(argv[1]);
    // const uint32_t B = atoi(argv[2]);

    printf("Testing parallel basic blocks for input length: %d and CUDA-block size: %d\n\n\n", N, B);

    const size_t mem_size = N*sizeof(int32_t);
    int32_t* h_in    = (int32_t*) malloc(mem_size);
    int32_t* d_in;
    int32_t* d_out;
    cudaMalloc((void**)&d_in ,   mem_size);
    cudaMalloc((void**)&d_out,   mem_size);

		int32_t h_start[16] = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1};
		// int32_t h_start[16] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};

    // initArray(h_in, N, 1);
		for (uint32_t i = 0; i < 16; i++) {
			h_in[i] = h_start[i];
		}
    cudaMemcpy(d_in, h_in, mem_size, cudaMemcpyHostToDevice);
 
    {
			spsTests(N, h_in, d_in, d_out);
    }
    // {
    //     singlePassScan(B, N, h_in, d_in, d_out);
    // }


    // cleanup memory
    free(h_in);
    cudaFree(d_in );
    cudaFree(d_out);
}
