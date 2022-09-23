#import <Foundation/Foundation.h>

void XorSwap(int *x, int *y) {
	if(x!=y) {
		*x^=*y;
		*y^=*x;
		*x^=*y;
	}
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		
		srandom(CFAbsoluteTimeGetCurrent());

		const int W = 16;
		const int H = 8;
		
		int bx = random()%W;
		int ex = random()%W;
		if(bx>ex) XorSwap(&bx,&ex);
		
		int by = random()%H;
		int ey = random()%H;
		if(by>ey) XorSwap(&by,&ey);

		printf("x: %d-%d\n",bx,ex);
		printf("y: %d-%d\n\n",by,ey);
	
		unsigned int *plane = new unsigned int[W*H];
		
		for(int k=0; k<W*H; k++) {
			plane[k] = random()&1;
		}
		
		for(int i=0; i<H; i++) {
			for(int j=0; j<W; j++) {
				printf("%d,",plane[i*W+j]);
			}
			printf("\n");
		}
		int num = 0;
		for(int i=by; i<=ey; i++) {
			for(int j=bx; j<=ex; j++) {
				num += plane[i*W+j];
			}
		}
		printf("= %d\n",num);

		unsigned int *sum = new unsigned int[(W+1)*(H+1)];
		for(int k=0; k<(W+1)*(H+1); k++) {
			sum[k] = 0;
		}
		
		for(int i=1; i<H+1; i++) {
			int v = 0;
			for(int j=1; j<W+1; j++) {
				sum[i*(W+1)+j] = (v+=plane[(i-1)*W+(j-1)]);
			}
		}
	
		for(int j=0; j<W+1; j++) {
			int v = 0;
			for(int i=0; i<H+1; i++) {
				v+=sum[i*(W+1)+j];
				sum[i*(W+1)+j] = v;
			}
		}
		
		printf("\n");
		for(int i=0; i<H+1; i++) {
			for(int j=0; j<W+1; j++) {
				printf("%03d,",sum[i*(W+1)+j]);
			}
			printf("\n");
		}
		
		// TL TR
		// BL BR
		
		int TL = by*(W+1)+bx;
		int TR = by*(W+1)+(ex+1);
		int BL = (ey+1)*(W+1)+bx;
		int BR = (ey+1)*(W+1)+(ex+1);
		printf("= %d\n",(sum[BR]-sum[BL]-sum[TR]+sum[TL]));
		
		delete[] plane;
		delete[] sum;
	}
}