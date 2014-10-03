#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

#include <cuda.h>
#include <curand_kernel.h>
#include <stdio.h>

#include <math.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "debug.h"
#include "ray_tracing.h"

#include "kernel.h"


//Round a / b to nearest higher integer value
inline int iDivUp(int a, int b)
{
    return (a % b != 0) ? (a / b + 1) : (a / b);
}

//Align a to nearest higher multiple of b
inline int iAlignUp(int a, int b)
{
    return (a % b != 0) ? (a - a % b + b) : a;
}


//#define INITIALIZE_HACK


void generate_scene(t_sphere * spheres, int n_spheres, t_light * lights, int n_lights)
{
	int n_random_coord = n_spheres * 3  + n_lights * 3;
	int n_random_rad = n_spheres;
	int n_random_colors = n_spheres * 3;

	size_t n = n_random_coord + n_random_rad + n_random_colors;

	curandGenerator_t gen;
	float *devData, *hostData;
	hostData = (float *)calloc(n, sizeof(float));
	cudaMalloc((void **)&devData, n*sizeof(float));

	curandCreateGenerator(&gen, CURAND_RNG_PSEUDO_DEFAULT);
	curandSetPseudoRandomGeneratorSeed(gen, 
		(unsigned long long)time(NULL)); 

	curandGenerateUniform(gen, devData, n);
	cudaMemcpy(hostData, devData, n * sizeof(float), cudaMemcpyDeviceToHost);
	
	int j=0;
	for (int i=0; i<n_spheres; i++)
	{
		spheres[i].center.x = hostData[j + 0] * BOX_SIZE ;
		spheres[i].center.y = hostData[j + 1] * BOX_SIZE ;
		spheres[i].center.z = hostData[j + 2] * BOX_SIZE + DISTANCE ;
		spheres[i].radius = hostData[j + 3] * RADIUS_MAX + RADIUS_MIN;

		spheres[i].red   = hostData[j + 4] / (DEPTH_MAX-3);
		spheres[i].green = hostData[j + 5] / (DEPTH_MAX-3);
		spheres[i].blue  = hostData[j + 6] / (DEPTH_MAX-3);
		j+=7;
	}

	for (int i=0; i<n_lights; i++)
	{
		lights[i].x = hostData[j + 0] * BOX_SIZE; 
		lights[i].y = hostData[j + 1] * BOX_SIZE; 
		lights[i].z = hostData[j + 2] * DISTANCE + BOX_SIZE/2.0; 
		j+=3; 
	}



#ifdef INITIALIZE_HACK
	spheres[0].center.x=9.746 ;
	spheres[0].center.y=7.0 ;
	spheres[0].center.z=29.0 ;
	spheres[0].radius=0.815 ;
	spheres[0].red=0.683 ;
	spheres[0].green=0.133 ;
	spheres[0].blue=0.403  ;

	spheres[1].center.x=3.372 ;
	spheres[1].center.y=3.0 ;
	spheres[1].center.z=29.0 ;
	spheres[1].radius=2.810 ;
	spheres[1].red=0.305 ;
	spheres[1].green=0.156 ;
	spheres[1].blue=0.199  ;

	lights[0].x=15.878 ;
	lights[0].y=3.0 ;
	lights[0].z=29.0 ;

//	lights[1].x=6.518 ;
//	lights[1].y=6.930 ;
//	lights[1].z=31.367 ;
#endif



	curandDestroyGenerator(gen);
	cudaFree(devData);
	free(hostData);    
}



void ray_trace(unsigned char * pR, unsigned char * pG, unsigned char * pB, 
				int height, int width, int n_spheres, int n_lights)
{
	cudaEvent_t start=0, stop=0;
        float gpuTime = 0.0f;

	cudaError_t err;

//#define STACK_INCREASE
#ifdef STACK_INCREASE 
	size_t stack=0;
	cudaDeviceGetLimit(&stack, cudaLimitStackSize); 
	printf ("Cuda stack size %ld \n", stack);
	stack = 1536;
	printf ("Setting cuda stack size to %ld \n", stack);
	cudaDeviceSetLimit(cudaLimitStackSize, stack);
#endif

	//cudaDeviceSetCacheConfig(cudaFuncCachePreferL1);
	//cudaDeviceSetCacheConfig(cudaFuncCachePreferShared);

	cudaEventCreate (&start);
        cudaEventCreate (&stop);

	t_sphere * spheres = (t_sphere *) malloc (sizeof(t_sphere) * n_spheres);
	t_light * lights = (t_light *) malloc (sizeof(t_light) * n_lights);

	generate_scene(spheres, n_spheres, lights, n_lights);



#ifdef DEBUG
	print_spheres(spheres, n_spheres);
	print_lights(lights, n_lights);
#endif

	t_sphere * dev_spheres;
	t_light * dev_lights;

	cudaMalloc((void **)&dev_spheres,  sizeof(t_sphere) * n_spheres );
	cudaMalloc((void **)&dev_lights,  sizeof(t_light) * n_lights );

	cudaMemcpy(dev_spheres, spheres, sizeof(t_sphere) * n_spheres, cudaMemcpyHostToDevice);
	cudaMemcpy(dev_lights, lights, sizeof(t_light) * n_lights, cudaMemcpyHostToDevice);

	unsigned char * dev_image_red;
	unsigned char * dev_image_green;
	unsigned char * dev_image_blue;

	cudaMalloc((void **)&dev_image_red,   height * width *sizeof(unsigned char));
	cudaMalloc((void **)&dev_image_green, height * width *sizeof(unsigned char));
	cudaMalloc((void **)&dev_image_blue,  height * width *sizeof(unsigned char));

	cudaMemset(dev_image_red,   0, height * width *sizeof(unsigned char));
	cudaMemset(dev_image_green, 0, height * width *sizeof(unsigned char));
	cudaMemset(dev_image_blue,  0, height * width *sizeof(unsigned char));

	cudaEventRecord (start, 0);

	dim3 block(BLOCK_SIZE_X, BLOCK_SIZE_Y, 1);
	dim3 grid(iDivUp(width, block.x), iDivUp(height, block.y), 1);

#ifdef DEBUG
	printf ("Running kernel with block.x=%d block.y=%d \n", block.x, block.y);
	printf ("Running kernel with grid.x=%d grid.y=%d \n", grid.x, grid.y);
#endif

	kernel<<<grid,block>>>(dev_image_red, dev_image_blue, dev_image_green, 
			height, width, dev_spheres, n_spheres, dev_lights, n_lights); 

	err = cudaGetLastError(); 
	if (err != cudaSuccess) 
	{
		printf( "%s \n", cudaGetErrorString( err ) );
	}

	cudaMemcpy(pR, dev_image_red,  height * width *sizeof(unsigned char), cudaMemcpyDeviceToHost);
	cudaMemcpy(pB, dev_image_blue, height * width *sizeof(unsigned char), cudaMemcpyDeviceToHost);
	cudaMemcpy(pG, dev_image_green,height * width *sizeof(unsigned char), cudaMemcpyDeviceToHost);

	cudaEventRecord (stop, 0);
        cudaEventSynchronize(stop);
        cudaEventElapsedTime (&gpuTime, start, stop);

	printf("GPU ray tracing  \n");
        printf("time spent executing on GPU: %.2f milliseconds\n", gpuTime);

	cudaFree(dev_image_red);
	cudaFree(dev_image_green);
	cudaFree(dev_image_blue);

	cudaFree(dev_spheres);
	cudaFree(dev_lights);

	free (spheres);
	free (lights);

	cudaEventDestroy (start);
	cudaEventDestroy (stop);

	return ;
}


