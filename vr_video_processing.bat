@echo off
setlocal ENABLEDELAYEDEXPANSION
cd /D "%~dp0"



rem if you are looking to tweak extra stuff, maybe those are the settings you are looking for
set zoom=20
set smooth_camera_factor=15
set shakiness_camera_factor=10



rem fancy colors because to make readability somewhat better.
rem modified, original from here https://stackoverflow.com/questions/2048509/how-to-echo-with-different-colors-in-the-windows-command-line
set cRED=[31m
set cGREEN=[32m
set cYELLOW=[33m
set cCYAN=[36m
set fDEFAULT=[0m
set cUP1LINE=[1A
set fBOLD=[1A
set cDEFAULT=[0m
set cCOLUMN=[40G

set sWHITE=[90m
set sRED=[91m
set sGREEN=[92m
set sYELLOW=[93m
set sBLUE=[94m
set sMAGENTA=[95m
set sCYAN=[96m
set sWHITE=[97m






rem starting state of the terminal colors
echo %cDEFAULT%


set transforms_temp=motion_data_%random%.trf
set mkv_temp=%temp%\%random%%random%%random%%random%.mkv
set avs_temp=%temp%\%random%%random%%random%%random%.avs


set url_ffmpeg=https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full.7z
set url_avisynth=https://github.com/AviSynth/AviSynthPlus/releases/download/v3.7.0/AviSynthPlus_3.7.0_20210111.exe


set ffmpeg_prepend=-y -loglevel quiet -stats
set ffmpeg_decoder_opts=-c:v h264_cuvid
set ffmpeg_encoder_opts=-c:v h264_nvenc
set nvidia_decoder=1
set nvidia_encoder=1


Title ### vr video motion smoother thingy ###
echo %cCYAN%checking dependencies... 



call :test_thing "FFMPEG.exe available" "ffmpeg -version" "ffmpeg.exe seems to be missing, download the zip at %url_ffmpeg% and copy the file bin\ffmpeg.exe to the same folder as this script. %cd%"
if !error_test_thing!==1 call :fatal_error_pause

call :test_thing "FFPROBE.exe available" "ffprobe -version" "ffprobe.exe seems to be missing, download the zip at %url_ffmpeg% and copy the file bin\ffprobe.exe to the same folder as this script. %cd%"
if !error_test_thing!==1 call :fatal_error_pause

call :gen_avisynth_test
call :test_thing "FFMPEG supports Avisynth scripts" "ffmpeg -y -i %avs_temp% -t 0.1 -f null -" "You seem to be missing Avisynth, download it at %url_avisynth% or your FFMPEG current executable was compiled without avisynth support."
if !error_test_thing!==1 call :fatal_error_pause

call :test_thing "FFMPEG can use Nvidia h264 encoding" "ffmpeg -y -i %avs_temp% -c:v h264_nvenc -t 0.1 ^"!mkv_temp!^"" "Not required but recomended. This is only available on geforce GPUs and can speedup the process."
if !error_test_thing!==1 (
set ffmpeg_encoder_opts=-c:v libx264
set nvidia_encoder=0
)

call :test_thing "FFMPEG can use Nvidia h264 decoding" "ffmpeg -y -c:v h264_cuvid -i ^"!mkv_temp!^" -c:v h264_nvenc -t 0.1 -f null -" "Not required but recomended. This is only available on geforce GPUs and can speed up the process."
if !error_test_thing!==1 (
set ffmpeg_decoder_opts=
set nvidia_decoder=0
)



rem queryng from the registry where avisynth is installed
set AVISYNTH_FOLDER=none
FOR /F "tokens=2* delims= " %%a IN ('REG QUERY "HKEY_LOCAL_MACHINE\SOFTWARE\AviSynth" /v plugindir2_5') do set AVISYNTH_FOLDER=%%b

if "%AVISYNTH_FOLDER%"=="none" (
echo avisynth does not seem to be installed, could not find it in the registry.
call :fatal_error_pause
)



rem temporary file for the deshaken but still not interpolated motion
set mkv_temp=%cd%\pre_interp_deshaken_video_%random%.mkv



rem maybe the user will drag+drop the file onto the script file instead of the window?
if NOT "%~1"=="" (
	set input_motion="%~1"
	echo %cDEFAULT%
	echo Using "%~1" as the input file from the command line.
)else (
	rem Pergunta pro usuario as opcoes a utilizar
	echo %cDEFAULT%
	echo Type or drag and drop the input video file on this window to fill this field.
	set /P input_motion=Input file name:
)




rem check 
for /f "tokens=1* delims==" %%a in ('ffprobe -v quiet -i !input_motion! -print_format ini -show_streams ^2^>^&1') do (
	rem echo %%a -- %%b
	if "%%a"=="r_frame_rate" for /f "tokens=1 delims=/" %%f in ("%%b") do set ffprobe_r_frame_rate=%%f
	if "%%a"=="codec_name" set ffprobe_codec_name=%%b
	if "%%a"=="codec_type" set ffprobe_codec_type=%%b
	if "%%a"=="width" set ffprobe_width=%%b
	if "%%a"=="height" set ffprobe_height=%%b
	if "%%a"=="codec_name" set ffprobe_codec_name=%%b


	if "%%a"=="duration" (
		set ffprobe_duration=%%b
		if "!ffprobe_codec_type!"=="video" (
			echo %cCYAN%Input video format: %sYELLOW%!ffprobe_codec_name! !ffprobe_width!x!ffprobe_height!@!ffprobe_r_frame_rate!fps%cDEFAULT%
			
			rem warn if the captured framerate suck
			if /i "!ffprobe_r_frame_rate!" LEQ "60" echo %sRED%Warning:%cYELLOW% this video file does not seem to be a full framerate capture, OBS using "game capture" + match video fps to VR screen frequency is strongly recomended!. if not the result might suck.%cDEFAULT%
			
			rem warn if the video aspect ratio suck
			set /a aspect_ratio_100= ^(!ffprobe_width! * 100^) / !ffprobe_height!
			if /i "!aspect_ratio_100!" GTR "145" echo %sRED%Warning: %cYELLOW%the aspect ratio of the video seems too wide, the end result will likely be VERY zoomed in after deshaking!%cDEFAULT%
						
			rem warn if the input video stream format suck
			if NOT "!ffprobe_codec_name!"=="h264" (
				echo %sRED%Warning: %cYELLOW%the input video stream is not h264, decoding the input might be slower and wont use nvidia hardware acceleration.%cDEFAULT%
				set ffmpeg_decoder_opts=
				set nvidia_decoder=0				
			)
			
		)
	)
)


rem read some filename for the output
echo.
echo Type the name of the output file (without extension) or leave blank to generate automatically a filename.
set /P output_motion=Output file name:


rem empty field = random file name
if "%output_motion%"=="" (
set output_motion=interp_%random%.mp4
)else (
set output_motion=!output_motion!.mp4
)



rem ---------------------------------------------------
:ask_time
echo.
echo Input the start of the cut in the hh:mm:ss format or leave blank to use the whole video.
echo hh:mm:ss format like 01:10:12
set /p ts_start=Start timestamp:

if NOT "!ts_start!"=="" (

  for /f tokens^=1^,2^,3^ delims^=: %%a in ('echo !ts_start!') do (  
	call :trim_zeroes %%a
	set r_a=!num_ret!
	call :trim_zeroes %%b
	set r_b=!num_ret!
	call :trim_zeroes %%c
	set r_c=!num_ret!

	if "!r_c!"=="" (	
	if "!r_b!"=="" (	
	 set ts_start_secs=!r_a!
	) else (	  
	 set /a ts_start_secs=^( !r_a! * 60 ^) + !r_b!
	)	
	)else ( 
	 set /a ts_start_secs=^( !r_a! * 3600 ^) + ^( !r_b! * 60 ^) + !r_c!
	)   
  )
)



if NOT "!ts_start!"=="" (
	:ask_time_end
	echo.
	echo Input the end of the cut in the hh:mm:ss format
	set /p ts_end=End timestamp:
	if NOT "!ts_end!"=="" (
	 
	  for /f tokens^=1^,2^,3^ delims^=: %%a in ('echo !ts_end!') do (  
		call :trim_zeroes %%a
		set r_a=!num_ret!
		call :trim_zeroes %%b
		set r_b=!num_ret!
		call :trim_zeroes %%c
		set r_c=!num_ret!


		if "!r_c!"=="" (	
		if "!r_b!"=="" (	
		 set ts_end_secs=!r_a!
		) else (	  
		 set /a ts_end_secs=^( !r_a! * 60 ^) + !r_b!
		)	
		)else ( 
		 set /a ts_end_secs=^( !r_a! * 3600 ^) + ^( !r_b! * 60 ^) + !r_c!
		)   
	  )
	  
	  rem echo set /a duration_user=!ts_end_secs! - !ts_start_secs!
	  set /a duration_user=!ts_end_secs! - !ts_start_secs!

	  if !duration_user! LSS 0 (
	  echo.
	  echo ERROR: Check the timestamps, they seem invalid!
	  echo.
	  goto ask_time_end
	  )
	)
)


if NOT "!ts_start_secs!"=="" set ts_start_secs=-ss !ts_start_secs!
if NOT "!duration_user!"=="" set duration_user=-t !duration_user!

rem ---------------------------------------------------

rem ---------------------------------------------------


echo.
echo Dropping duplicate frames can improve motion smoothness if your gameplay video couldnt hit flawless performance,
echo but often causes a video desync if too many frames are dropped in an uneven rate.
echo.

choice /C YN /M "Drop duplicate frames?"
if "%ERRORLEVEL%"=="1" set mp_decimate_filter=mpdecimate=hi=3036:lo=640:frac=1.0,



set motion_file_temp=motion_data_%random%%random%.tmp

echo.
echo * %cGREEN%^(1/3^) %cCYAN%Processing the motion detection for the deshake filter...%cDEFAULT%
ffmpeg %ffmpeg_prepend% %ffmpeg_decoder_opts% !ts_start_secs! -i %input_motion% !duration_user! -vf "!mp_decimate_filter!vidstabdetect=shakiness=!shakiness_camera_factor!:accuracy=15:stepsize=6:mincontrast=0.3:result=!transforms_temp!" -f null -
if ERRORLEVEL 1 echo fatal ffmpeg error! && call :fatal_error_pause

echo.
echo * %cGREEN%^(2/3^) %cCYAN%Rendering the deshaken intermediary file...%cDEFAULT%
ffmpeg %ffmpeg_prepend% %ffmpeg_decoder_opts% !ts_start_secs! -i %input_motion% !duration_user! -vf "!mp_decimate_filter!vidstabtransform=smoothing=!smooth_camera_factor!:interpol=linear:crop=black:zoom=!zoom!:input=!transforms_temp!,unsharp=5:5:0.8:3:3:0.4,format=yuv420p" !ffmpeg_encoder_opts! -preset fast -rc:v vbr_minqp -qmin:v 1 -qmax:v 18 !mkv_temp!
if ERRORLEVEL 1 echo fatal ffmpeg error! && call :fatal_error_pause

rem generate the avisynth script that does the motion interpolation
call :gen_avisynth_script

echo.
echo * %cGREEN%^(3/3^) %cCYAN%Rendering the final file with motion interpolation...^(This step is VERY slow!^) %cDEFAULT%
ffmpeg %ffmpeg_prepend% -i "%avs_temp%" -i !mkv_temp! -map 0:v:0 -map 1:a:0 -c:a copy !ffmpeg_encoder_opts! -rc:v vbr_minqp -qmin:v 1 -qmax:v 28 "%output_motion%"
if ERRORLEVEL 1 echo fatal ffmpeg error! call :fatal_error_pause


rem cleanup, delete temporary files
del !transforms_temp! >NUL 2>NUL
del "%avs_temp%" >NUL 2>NUL
del "%mkv_temp%" >NUL 2>NUL

echo.
echo %cGREEN%all done! %cYELLOW% %output_motion%


::aguardar 3 segundos
timeout 3 /nobreak >NUL 2>NUL
goto :eof




:: end of the main function
::================================================================
::================================================================
:: other functions and weird stuff
::================================================================
::================================================================

:fatal_error_pause
pause
exit
goto :eof

::================================================================
:test_thing
echo %cDEFAULT%%~1 %cCOLUMN%%cYELLOW%[...]
%~2 >NUL 2>NUL
if ERRORLEVEL 1 (
echo %cUP1LINE%%cDEFAULT%%~1 %cCOLUMN%%cRED%[FAIL]    
echo.
echo %cDEFAULT% %~3
echo.
set error_test_thing=1
exit /B
)else (
echo %cUP1LINE%%cDEFAULT%%~1 %cCOLUMN%%cGREEN%[OK]    
set error_test_thing=0

)

goto :eof




::================================================================
:gen_avisynth_script

rem echo loadplugin^(^"%ProgramFiles(x86)%\AviSynth+\plugins64\ffms2.dll^"^) >%avs_temp%
echo loadplugin^(^"!AVISYNTH_FOLDER!\ffms2.dll^"^) >%avs_temp%
echo loadplugin^(^"!AVISYNTH_FOLDER!\mvtools2.dll^"^)>>%avs_temp%
echo SetFilterMTMode^(^"DEFAULT_MT_MODE^", 2^)>>%avs_temp%
echo SetFilterMTMode^(^"FFVideoSource^", 3^)>>%avs_temp%
rem echo A = FFAudioSource^(^"%input_motion%^"^)>>%avs_temp%
echo V = FFVideoSource^(^"!mkv_temp!^"^)>>%avs_temp%
rem echo source = AudioDub^(V, A^)>>%avs_temp%
echo source = V >>%avs_temp%
echo super = MSuper^(source, pel=2^)>>%avs_temp%
echo backward_vectors = MAnalyse^(super, blksize=8, overlap=4, isb=true, dct=1, search=3^)>>%avs_temp%
echo forward_vectors = MAnalyse^(super, blksize=8, overlap=4, isb=false, dct=1, search=3^)>>%avs_temp%
echo MFlowFps^(source, super, backward_vectors, forward_vectors, num=960000, den=1000, ml=100^)>>%avs_temp%
echo Merge^(SelectEven^(^), SelectOdd^(^)^)>>%avs_temp%
echo Merge^(SelectEven^(^), SelectOdd^(^)^)>>%avs_temp%
echo Merge^(SelectEven^(^), SelectOdd^(^)^)>>%avs_temp%
echo Merge^(SelectEven^(^), SelectOdd^(^)^)>>%avs_temp%
echo Prefetch^(%NUMBER_OF_PROCESSORS%^)>>%avs_temp%
goto :eof

::================================================================
:gen_avisynth_test
echo Version^(^)>%avs_temp%
goto :eof



::===================================================================
:trim_zeroes
set num_ret=%1
 :loop_trim_zeroes 
 if "%num_ret:~0,1%"=="0" (
 set num_ret=%num_ret:~1,999%
 
 if "!num_ret!"=="0" (
 goto :eof
 )
  
 goto loop_trim_zeroes
 )
goto :eof

