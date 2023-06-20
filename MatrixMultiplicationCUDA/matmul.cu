#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <math.h>
#include <stdio.h>
#include <time.h>
#include <iostream>
#include <stdlib.h>
#include "GpuTimer.h"
using namespace std;

#define BLOCK_SIZE 16

void matMulCPU(float* A, float* B, float* C, int numARows, int numACols, int numBCols) {
    int i, j, k;
    int offsetA, offsetB;
    float cumSum;

    for (i = 0; i < numARows; i++) {
        for (j = 0; j < numBCols; j++) {
            cumSum = 0;
            for (k = 0; k < numACols; k++) {
                // linearize index
                offsetA = i*numACols + k;
                offsetB = k*numBCols + j;

                // accumulate element-wise product
                cumSum += A[offsetA] * B[offsetB];
            }
            C[i*numBCols + j] = cumSum;
        }
    }
}

__global__ void matMulGPU(float* A, float* B, float* C, int numARows, int numACols, int numBCols) {
    // compute global thread coordinates
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;

    // linearize coordinates for data access
    int offset = row * numBCols + col;

    if ((row < numARows) && (col < numBCols)) {
        float cumSum = 0;
        for (int k = 0; k < numACols; k++) {
            cumSum += A[row*numACols + k] * B[k*numBCols + col];
        }
        C[offset] = cumSum;
    }
}


int main(int argc, char* argv[]) {
    int numARows = 960;
    int numACols = 640;
    int numBCols = 800;

    if (argc ==4 ) {
        numARows = std::stoi(argv[1]);
        numACols = std::stoi(argv[2]);
        numBCols = std::stoi(argv[3]);
    }

    cout<<"Size of matrix A: "<<numARows<<" "<<numACols<<endl;
    cout<<"Size of matrix B: "<<numACols<<" "<<numBCols<<endl;    

    // timers
    GpuTimer timer0, timer1, timer2, timer3;

    size_t sizeA = numARows * numACols * sizeof(float);
    size_t sizeB = numACols * numBCols * sizeof(float);
    size_t sizeC = numARows * numBCols * sizeof(float);


    // allocate host memory
    float* h_A = (float*)malloc(sizeA);
    float* h_B = (float*)malloc(sizeB);
    float* h_C = (float*)malloc(sizeC);
    float* h_C_CPU = (float*)malloc(sizeC);

    // initialize host matrices
    int i, j, offset;
    for (i = 0; i <  numARows; i++) {
        for (j = 0; j < numACols; j++) {
            offset = i*numACols + j;
            h_A[offset] = sin(i);
        }
    }
    for (i = 0; i <  numACols; i++) {
        for (j = 0; j < numBCols; j++) {
            offset = i*numBCols + j;
            h_B[offset] = cos(j);
        }
    }

    // allocate device matrices
    float* d_A;
    float* d_B;
    float* d_C;
    timer0.Start();
    cudaMalloc((void**)&d_A, sizeA);
    cudaMalloc((void**)&d_B, sizeB);
    cudaMalloc((void**)&d_C, sizeC);
    timer0.Stop();
    printf("Time to allocate memory on the device is: %f msecs.\n", timer0.Elapsed());

    // transfer to GPU
    timer1.Start();
    cudaMemcpy(d_A, h_A, sizeA, cudaMemcpyHostToDevice);
    cudaMemcpy(d_B, h_B, sizeB, cudaMemcpyHostToDevice);
    timer1.Stop();
    printf("Time to copy the Matrix from host to device is: %f msecs.\n", timer1.Elapsed());

    // kernel launch
    dim3 threadPerBlock(BLOCK_SIZE, BLOCK_SIZE, 1);
    dim3 blockPerGrid(ceil(numBCols/(float)BLOCK_SIZE), ceil(numACols/(float)BLOCK_SIZE), 1);
    timer2.Start();
    matMulGPU<<<blockPerGrid, threadPerBlock>>>(d_A, d_B, d_C, numARows, numACols, numBCols);
    timer2.Stop();
    printf("Implemented CUDA code ran in: %f msecs.\n", timer2.Elapsed());

    // transfer to CPU
    timer3.Start();
    cudaMemcpy(h_C, d_C, sizeC, cudaMemcpyDeviceToHost);
    timer3.Stop();
    printf("Time to copy the resulting Matrix from device to host is: %f msecs.\n", timer3.Elapsed());

    clock_t begin = clock();
    matMulCPU(h_A, h_B, h_C_CPU, numARows, numACols, numBCols);
    clock_t end = clock();
    double time_spent = (double)(end - begin) / CLOCKS_PER_SEC * 1000;
    printf("Implemented CPU code ran in: %f msecs.\n", time_spent);

    free(h_A); free(h_B); free(h_C); free(h_C_CPU);
    cudaFree(d_A); cudaFree(d_B); cudaFree(d_C);
    printf("Done");

    return 0;
}