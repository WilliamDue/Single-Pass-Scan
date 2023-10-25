#ifndef SPS_CU_H
#define SPS_CU_H

#include <cuda_runtime.h>

#include "constants.cu.h"

#define X 0
#define A 1
#define P 2

// template <int B, int Q>
// __device__ inline void threadReduce(int32_t *shd_mem, uint32_t idx) {
//     unsigned int tid = threadIdx.x;
//     int acc = 0;
// #pragma unroll
//     for (int i = 0; i < Q; i++) {
//         int tmp = shd_mem[idx + i * B + tid];
//         acc = acc + tmp;
//     }
//     // stores acc in the auxiliary array
//     aux_mem[idx + 4 * B + tid] = acc;
// }

// shd_mem is a pointer to an array in shared memory. It has size Q * B.
// idx is the id of the part of the shared memory we start scanning.
template <int B, int Q>
__device__ inline void threadScan(int32_t *shd_mem) {
    unsigned int tid = threadIdx.x;
    int acc = 0;
#pragma unroll
    for (int = 0; i < Q; i++) {
        int tmp = shd_mem[i * B + tid];
        acc = acc + tmp;
        shd_mem[i * B + tid] = acc;
    }
}

template <int B, int Q>
__device__ inline void threadAdd(int32_t *shd_mem, int32_t *shd_buf) {
    unsigned int tid = threadIdx.x;
#pragma unroll
    if (tid != 0) {
        int32_t tmp = shd_buf[tid - 1];
        for (int = 0; i < Q; i++) {
            shd_mem[i * B + tid] = shd_mem[i * B + tid] + tmp;
        }
    }
}

// Function that uses collectively scans a warp of elements in a shared buffer.
// shd_buf is a pointer to an array in shared memory. It has size B <= 1024.
// idx is the id of the part of the shared memory we start scanning.
//
// Each thread in the warp performs a scan across the shared buffer. The
// result is stored in the shared buffer.
__device__ inline int32_t warpScan(volatile int32_t *shd_buf, uint32_t idx,
                                   int32_t) {
    uint32_t lane = idx & (WARP - 1);  // WARP
    int n = WARP;
    int k = lgWARP;

#pragma unroll
    for (int d = 0; d < k; d++) {
        int h = 1 << d;
        if (lane >= h) {
            shd_buf[idx] = shd_buf[idx - h] + shd_buf[idx];
        }
    }

    int32_t res = shd_buf[idx];
    return res;
}

// Function that performs a per block scan collectively across all threads in
// the block.
// shd_buf is a pointer to an array of size B.
// idx is the id of the part of the shared memory we start scanning.
//
// Each thread copy the final value of the scan to the shd_buf. Then
// we perform a parallel scan across the shd_buf like in assignment 2.
template <int B, int Q>
__device__ inline int32_t blockScan(volatile int32_t *shd_buf, uint32_t idx) {
    uint32_t lane = idx & (WARP - 1);
    uint32_t warpid = idx >> lgWARP;

    // scan at warp level
    int64_t warp_res = warpScan(shd_buf, idx);
    __syncthreads();

    // store the results of each warp scan in the first part of the shared
    // memory
    if (lane == WARP - 1) {
        shd_buf[warpid] = warp_res;
    }
    __syncthreads();

    // scan the first warp again.
    if (warpid == 0) {
        warpScan(shd_buf, idx);
    }

    // accumulate the results from the previous step
    if (warpid > 0) {
        int32_t tmp = shd_buf[warpid - 1];
        warp_res = warp_res + tmp;
    }

    return warp_res;
}

// aux_mem is an index to an array of global memory.
// flag_mem is an array with flags corresponding to which aux_mem indices
//     are valid.
// aux_size is the size of the aux_mem array Performs a scan a across aux
//     array and stores the result in aux_mem.
//
// The function sequentially scans all elements in the aux array and stores
// the result in aux_mem. For each position in the aux_mem, wait to progress
// until the flag_mem is set to 1. This is done by checking the flag_mem
// array in a loop. Once the flag_mem is set to 1, thread can update the
// aux_mem array.
template <int B, int Q>
__device__ inline void blockLevelScan(int32_t *aux_mem, int32_t *flag_mem,
                                      uint32_t aux_size) {
    uint32_t tid = threadIdx.x;
    if (tid == 0) {
        // scan the aux array
        for (int i = 1; i < aux_size; i++) {
            // wait for the flag to be set
            while (flag_mem[i] == 0)
                ;
            // update the aux array
            aux_mem[i] = aux_mem[i] + aux_mem[i - 1];
        }
    }
}

#endif /* SPS_CU_H */

/**
 * Naive memcpy kernel, for the purpose of comparing with
 * a more "realistic" bandwidth number.
 */
__global__ void naiveMemcpy(int* d_out, int* d_inp, const uint32_t N)
{
	uint32_t gid = blockIdx.x * blockDim.x + threadIdx.x;
	if (gid < N) {
		d_out[gid] = d_inp[gid];
	}
}


/**
 * Helper function that copies `Q` input elements per thread from
 *   global to shared memory, in a way that optimizes spatial locality,
 *
 * `glb_offs` is the offset in global-memory array `d_inp`
 *    from where elements should be read.
 * `d_inp` is the input array stored in global memory
 * `N` is the length of `d_inp`
 * `ne` is the neutral element of `T` (think zero). In case
 *    the index of the element to be read by the current thread
 *    is out of range, then place `ne` in shared memory instead.
 * `shmem_inp` is the shared memory. It has size
 *     `blockDim.x*CHUNK*sizeof(T)`, where `blockDim.x` is the
 *     size of the CUDA block. `shmem_inp` should be filled from
 *     index `0` to index `blockDim.x*CHUNK - 1`.
 *
 * As such, a CUDA-block B of threads executing this function would
 *   read `Q*B` elements from global memory and store them to
 *   (fast) shared memory, in the same order in which they appear
 *   in global memory, but making sure that consecutive threads
 *   read consecutive elements of `d_inp` in a SIMD instruction.
 **/
template <class T, uint32_t Q>
__device__ inline void
copyFromGlb2ShrMem(const uint32_t glb_offs, const uint32_t N, const T& ne, T* d_inp, volatile T* shmem_inp)
{
#pragma unroll
	for (uint32_t i = 0; i < Q; i++) {
		uint32_t loc_ind = blockDim.x * i + threadIdx.x;
		uint32_t glb_ind = glb_offs + loc_ind;
		T elm = ne;
		if (glb_ind < N) {
			elm = d_inp[glb_ind];
		}
		shmem_inp[loc_ind] = elm;
	}
	__syncthreads();	// leave this here at the end!
}

/**
 * This is very similar with `copyFromGlb2ShrMem` except
 * that you need to copy from shared to global memory, so
 * that consecutive threads write consecutive indices in
 * global memory in the same SIMD instruction.
 * `glb_offs` is the offset in global-memory array `d_out`
 *    where elements should be written.
 * `d_out` is the global-memory array
 * `N` is the length of `d_out`
 * `shmem_red` is the shared-memory of size
 *    `blockDim.x*Q*sizeof(T)`
 */
template <class T, uint32_t Q>
__device__ inline void
copyFromShr2GlbMem(const uint32_t glb_offs, const uint32_t N, T* d_out, volatile T* shmem_red)
{
#pragma unroll
	for (uint32_t i = 0; i < Q; i++) {
		uint32_t loc_ind = blockDim.x * i + threadIdx.x;
		uint32_t glb_ind = glb_offs + loc_ind;
		if (glb_ind < N) {
			T elm = const_cast<const T&>(shmem_red[loc_ind]);
			d_out[glb_ind] = elm;
		}
	}
	__syncthreads();	// leave this here at the end!
}

__device__ inline int getDynID(int* IDAddr){
	return AtomicAdd(IDAddr,1);
}


template <int B, int Q>
__global__ void SinglePassScanKernel(int32_t* d_in, uint32_t N, uint32_t* IDAddr,
                 uint32_t* flagArr, uint32_t* aggrArr, uint32_t* prefixArr, uint32_t numBlocks){

    // Step 1 get a dynamic id
    dynID = getDynID(IDAddr);
    // Step 1.5 calculate some id's and stuff we will use
    globaloffSet = dynID*B*Q;
    // Step 2 copy the memory the block will scan into shared memory.
    __shared__ int32_t blockShrMem[B*Q];
    copyFromGlb2ShrMem<uint32_t, Q>(globaloffset, N, 0, blockShrMem);

    // Step 3 Do the scan on the block
    // First scan each thread
    Thread_scan<B,Q>(blockShrMem);
    // Do the scan on the block level
    int32_t res = blockScan<B,Q>(blockShrMem, threadIdx.x);
    // Save the result in shrmem.
    blockShrMem[threadIdx.x] = res;

    // Step 4 Update aggregate array
    if (threadIdx.x == B-1){
        aggrArr[dynID] = res
        __threadfence()
        flagArr[dynID] = A
    }

    // Let block 0 calculate 

    // Step 5 calculate prefixArr value, might block or wait.

    // Step 6 Update prefix array

    // Step 7 Sum the prefix into the scan

    // Step 8 Copy the result into global memory

    // Step 9 Die!
}

    /*** Steps for the kernel in general and for other Kernel ***/

    // Step 0 calculate some id's and stuff we will use

    // Step 1 get a dynamic id

    // Step 2 copy the memory the block will scan into shared memory.

    // Step 3 Do the scan on the block

    // Step 4 Update aggregate array

    // Step 5 calculate prefixArr value, might block or wait.

    // Step 6 Update prefix array

    // Step 7 Sum the prefix into the scan

    // Step 8 Copy the result into global memory

    // Step 9 Die!