import("stdfaust.lib");
declare nvoices "8";
noisegain = hslider("noise_gain [unit:dB][tooltip: Noise Level in decibells]",-20,-70,0,0.01);
damping_freq = hslider("damping_freq[unit:Hz][tooltip: Dumping frequency of Open Tube]",5000,100,18000,0.01);

nonl1 = hslider("h:nonlinearity/nonl_1st",1,-1,1,0.001);
nonl2 = hslider("h:nonlinearity/nonl_2nd",0,-1,1,0.001);
nonl3 = hslider("h:nonlinearity/nonl_3rd",-1,-1,1,0.001);

recursion_gain = hslider("recursion_gain",0.9,0,1,0.001);
tonehole_scatter = hslider("tonehole_scatter_ratio",0.8,0,1,0.001);
tonehole_position = hslider("tonehole_position",1,1,16,1);


blow_position = hslider("blow_position[tooltip:blow position of AirReed]",0.5,0.25,0.75,0.001);

lip_mix = hslider("lip_mix",0.2,0,1,0.001);
lip_tension = hslider("lip_tension",0.5,0,1,0.001);

base_freq = hslider("freq[unit:Hz]",440,20,20000,0.01);
bend = hslider("bend[midi:pitchwheel]",1,0,10,0.01) : si.polySmooth(gate,0.999,1);

freq = base_freq*bend;

gain = hslider("gain[style:knob]",0.6,0,1,0.01);

envAttack = hslider("h:[0]midi/[3]envAttack[unit:ms][style:knob]",100,0,1000,0.01)*0.001;
envDecay = hslider("h:[0]midi/[3]envDecay[unit:ms][style:knob]",100,0,1000,0.01)*0.001;
envSustain = hslider("h:[0]midi/[3]envSustain[style:knob]",0.8,0,1,0.01)*100;
envRelease = hslider("h:[0]midi/[3]envRelease[unit:ms][style:knob]",100,0,3000,0.01)*0.001;

envCurve = hslider("h:[0]midi/[3]envCurve[style:knob]",1,0,1,0.01);

s = hslider("h:[0]midi/[4]sustain[hide:1][midi:ctrl 64][style:knob]",0,0,1,1);
t = button("gate");
gate = t+s : min(1);

vibrato_rate = hslider("h:/vibrato/vibrato_rate[unit:Hz][style:knob]",5,0.01,20,0.01);
vibrato_depth= hslider("h:/vibrato/vibrato_depth[style:knob]",0.3,0,1,0.01);
vibrato_delay= hslider("h:/vibrato/vibrato_delay[style:knob]",1000,0,2000,0.01)*0.001;
vibrato_sharpness= hslider("h:/vibrato/vibrato_sharpness[unit:Hz][style:knob]",20,0.001,20,0.001);
vibrato_shape= hslider("h:/vibrato/vibrato_shape[unit:Hz][style:knob]",0.7,0,1,0.001);

// Excitation

vibratoOsc(freq,ratio) = os.lf_sawpos(freq)<:(pospart,negpart):>_
with{
  pospart(in) = in<: (>(ratio)) , (in/ratio):*;
  negpart(in) = in<: (<=(ratio)), (1-(in/ratio)) :*;
};

vib_envelope = gate:en.asr(vibrato_delay,vibrato_depth*100,envRelease);

vibrato_wave = vibratoOsc(vibrato_rate,vibrato_shape): fi.lowpass(1,vibrato_sharpness):*(vib_envelope):*(vibrato_depth);

envelope     = gate:en.adsr(envAttack,envDecay,envSustain,envRelease):*(1-vibrato_wave)*(gain);

// LipFilter frequency is sync to base frequency

lipfilter(freq) =fi.tf2(b0,b1,b2,a1,a2)
with{
  tension_multiple = pow(4,(2*lip_tension)-1);
  lip_freq = freq*tension_multiple;
  Q = 0.997;
  b0=1;b1=0;b2=0;
  a1=-2*Q*cos(3.14159*2*lip_freq/ma.SR);
  a2=Q<:*;
};

blow_noise = no.noise;

blow_signal(env) = env*blow_noise:*(noisegain:ba.db2linear) + env;

// TODO:Is Last Clipping Section atan right...?

nonlinearity = _<:(_,(*<:_,_),_):(_,_,*):(*(nonl1),*(nonl2),*(nonl3)):>atan;

MAX_DELAY = 48000;

jet_delay(freq,blowpos) = de.fdelay(MAX_DELAY,time)
with{
  time = (ma.SR/freq) :*(blowpos);
};

bore_delay(freq)=de.fdelay(MAX_DELAY,time)
with{
  time = (ma.SR/freq);
};
tonehole_delay(freq,division)=de.fdelay(MAX_DELAY,time)
with{
  time = (ma.SR/freq)/division;
};

damp_filter = fi.lowpass(1,damping_freq);

mix(m) = (_*(1-m)),(_*m) :>_; //m=0~1


//TODO:is Distribute gain right?
whirlwind_body(env,freq)= (( ( (+(blow_signal(env)) <:(_,lipfilter_dim):mix(lip_mix):jet:nonlinearity),_):+:damp_filter<:(_,_)) ~( (bore,th)<:(+,+):(*(0.4),*(0.5)) ) ) :(_,!):*(env)
with{
  lipfilter_dim=*(0.01):lipfilter(freq);//TODO : is dimmer coefficient right?
  jet = jet_delay(freq,blow_position);
  bore = bore_delay(freq)*(1-tonehole_scatter)*recursion_gain;
  th = tonehole_delay(freq,tonehole_position)*recursion_gain*tonehole_scatter;
};

process = whirlwind_body(envelope,freq);
