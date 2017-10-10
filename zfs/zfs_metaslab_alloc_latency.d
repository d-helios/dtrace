#!/usr/sbin/dtrace -s

#pragma D option quiet

dtrace:::BEGIN
{
        printf("Tracing... Hit Ctrl-C to end.\n");
}

::metaslab_alloc:entry 
{ 
	self->ts = timestamp
} 

::metaslab_alloc:return 
/ self->ts /
{ 
	this->elapsed = timestamp - self->ts; 
	@lat["Time(us)"] = quantize(this->elapsed/1000); 
	self->ts = 0
} 

tick-5sec { printa(@lat); trunc(@lat) }
