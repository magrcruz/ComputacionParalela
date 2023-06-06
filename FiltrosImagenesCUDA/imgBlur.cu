// imgBlur.cu
// Comando para compilar el codigo
// nvcc -I/usr/include/opencv4 -L/usr/lib -o imgBlur imgBlur.cu -lopencv_core -lopencv_highgui -lopencv_imgcodecs

#include <opencv2/core/core.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/highgui/highgui.hpp>
#include<opencv2/opencv.hpp>
#include <iostream>
#include <cuda_runtime.h>
#include "device_launch_parameters.h"
#include "GpuTimer.h"
#include<time.h>

using namespace cv;
using namespace std;

#define CV_LOAD_IMAGE_COLOR cv::IMREAD_COLOR
#define CV_LOAD_IMAGE_GRAYSCALE cv::IMREAD_GRAYSCALE
#define FILTER_SIZE 11
#define BLOCK_SIZE 16

// imgBlurCPU blurs an image on the CPU
void imgBlurCPU(unsigned char* outImg, unsigned char* inImg, int width, int height) {
    int cumSum, numPixels;
    int cornerRow, cornerCol;
    int filterRow, filterCol;
    int filterSize = 2*FILTER_SIZE + 1;

    // loop through the pixels in the output image
    for (int row = 0; row < height; row++) {
        for (int col = 0; col < width; col++) {
            // compute coordinates of top-left corner
            cornerRow = row - FILTER_SIZE;
            cornerCol = col - FILTER_SIZE;

            // reset accumulator
            numPixels = 0;
            cumSum = 0;

            // accumulate values inside filter
            for (int i = 0; i < filterSize; i++) {
                for (int j = 0; j < filterSize; j++) {
                    // compute pixel coordinates inside filter
                    filterRow = cornerRow + i;
                    filterCol = cornerCol + j;

                    // make sure we are within image boundaries
                    if ((filterRow >= 0) && (filterRow <= height) && (filterCol >= 0) && (filterCol <= width)) {
                        // accumulate sum
                        cumSum += inImg[filterRow*width + filterCol];
                        numPixels++;
                    }
                }
            }
            // set the value of output
            outImg[row*width + col] = (unsigned char)(cumSum / numPixels);
        }
    }
}

// imgBlurGPU blurs an image on the GPU
__global__ void imgBlurGPU(unsigned char* outImg, unsigned char* inImg, int width, int height) {
    int filterRow, filterCol;
    int cornerRow, cornerCol;
    int tx = threadIdx.x; int ty = threadIdx.y;
    int bx = blockIdx.x; int by = blockIdx.y;
    int filterSize = 2*FILTER_SIZE + 1;

    // compute global thread coordinates
    int row = by * blockDim.y + ty;
    int col = bx * blockDim.x + tx;

    // make sure thread is within image boundaries
    if ((row < height) && (col < width)) {
        // instantiate accumulator
        int numPixels = 0;
        int cumSum = 0;

        // top-left corner coordinates
        cornerRow = row - FILTER_SIZE;
        cornerCol = col - FILTER_SIZE;

        // accumulate values inside filter
        for (int i = 0; i < filterSize; i++) {
            for (int j = 0; j < filterSize; j++) {
                // filter coordinates
                filterRow = cornerRow + i;
                filterCol = cornerCol + j;

                // accumulate sum
                if ((filterRow >= 0) && (filterRow <= height) && (filterCol >= 0) && (filterCol <= width)) {
                    cumSum += inImg[filterRow*width + filterCol];
                    numPixels++;
                }
            }
        }
        // set the value of output
        outImg[row*width + col] = (unsigned char)(cumSum / numPixels);
    }
}

int main(int argc, char *argv[]) {
    // make sure filename given
    if (argc == 1) {
        printf("[!] Filename expected.\n");
        return 0;
    }

    // read image
    Mat img;
    img = imread(argv[1], CV_LOAD_IMAGE_GRAYSCALE);
    if (img.empty()) {
        printf("Cannot read image file %s", argv[1]);
        exit(1);
    }

    // define img params and timers
    int imgWidth = img.cols;
    int imgHeight = img.rows;
    size_t imgSize = sizeof(unsigned char)*imgWidth*imgHeight;
    GpuTimer timer, timer1, timer2, timer3;

    // allocate mem for host output image vectors
    unsigned char* h_outImg = (unsigned char*)malloc(imgSize);
    unsigned char* h_outImg_CPU = (unsigned char*)malloc(imgSize);

    // grab pointer to host input image
    unsigned char* h_inImg = img.data;

    // allocate mem for device input and output
    unsigned char* d_inImg;
    unsigned char* d_outImg;
    timer.Start();
    cudaMalloc((void**)&d_inImg, imgSize);
    cudaMalloc((void**)&d_outImg, imgSize);
    timer.Stop();
    float d_t0 = timer.Elapsed();
    printf("Time to allocate memory on the device is: %f msecs.\n", d_t0);

    // copy the input image from the host to the device and record the needed time
    timer1.Start();
    cudaMemcpy(d_inImg, h_inImg, imgSize, cudaMemcpyHostToDevice);
    timer1.Stop();
    float d_t1 = timer1.Elapsed();
    printf("Time to copy the input image from the host to the device is: %f msecs.\n", d_t1);

    // execution configuration parameters + kernel launch
    dim3 dimBlock(16, 16, 1);
    dim3 dimGrid(ceil(imgWidth/16.0), ceil(imgHeight/16.0), 1);
    timer2.Start();
    imgBlurGPU<<<dimGrid, dimBlock>>>(d_outImg, d_inImg, imgWidth, imgHeight);
    timer2.Stop();
    float d_t2 = timer2.Elapsed();
    printf("Implemented CUDA code ran in: %f msecs.\n", d_t2);

    // copy output image from device to host
    timer3.Start();
    cudaMemcpy(h_outImg, d_outImg, imgSize, cudaMemcpyDeviceToHost);
    timer3.Stop();
    float d_t3 = timer.Elapsed();
    printf("Time to copy the Gray image from the device to the host is: %f msecs.\n", d_t3);

    // do the processing on the CPU
    clock_t begin = clock();
    imgBlurCPU(h_outImg_CPU, h_inImg, imgWidth, imgHeight);
    clock_t end = clock();

    // calculate total time for CPU and GPU
    double time_spent = (double)(end - begin) / CLOCKS_PER_SEC*1000;
    printf("Total CPU code ran in: %f msecs.\n", time_spent);
    float total_device_time = d_t0 + d_t1 + d_t2 + d_t3;
    printf("Total GPU code ran in: %f msecs.\n", total_device_time);
    float speedup = (float)time_spent / total_device_time;
    printf("GPU Speedup: %f\n", speedup);

    Mat Image1(imgHeight, imgWidth, CV_8UC1, h_outImg);
    Mat Image2(imgHeight, imgWidth, CV_8UC1, h_outImg_CPU);
    imwrite("ImagenBlur.jpg", Image1);
    imwrite("ImagenBlurCPU.jpg", Image2);

    // free host and device memory
    img.release(); Image1.release(); Image2.release();
    free(h_outImg_CPU); free(h_outImg);
    cudaFree(d_outImg); cudaFree(d_inImg);

    return 0;
}