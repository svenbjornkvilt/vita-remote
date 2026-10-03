use crate::{Frame, Pixfmt};
use lazy_static::lazy_static;
use std::{
    io,
    sync::Mutex,
    time::{Duration, Instant},
};

// Frames are pushed by the ReplayKit broadcast extension, already downscaled, as BGRA.
#[derive(Default)]
struct LatestFrame {
    data: Vec<u8>,
    width: usize,
    height: usize,
    stride: usize,
    seq: u64,
}

lazy_static! {
    static ref LATEST: Mutex<LatestFrame> = Default::default();
}

const FIRST_FRAME_WAIT: Duration = Duration::from_secs(2);

pub fn push_frame(data: &[u8], width: usize, height: usize, stride: usize) {
    if width == 0 || height == 0 || stride < width * 4 || data.len() < stride * height {
        return;
    }
    let mut latest = LATEST.lock().unwrap();
    latest.data.clear();
    latest.data.extend_from_slice(&data[..stride * height]);
    latest.width = width;
    latest.height = height;
    latest.stride = stride;
    latest.seq = latest.seq.wrapping_add(1);
}

pub fn clear_frames() {
    *LATEST.lock().unwrap() = Default::default();
}

fn latest_size() -> (usize, usize) {
    let latest = LATEST.lock().unwrap();
    (latest.width, latest.height)
}

pub struct Capturer {
    width: usize,
    height: usize,
    stride: usize,
    data: Vec<u8>,
    seq: u64,
}

impl Capturer {
    pub fn new(display: Display) -> io::Result<Capturer> {
        Ok(Capturer {
            width: display.width,
            height: display.height,
            stride: 0,
            data: Vec::new(),
            seq: 0,
        })
    }

    pub fn width(&self) -> usize {
        self.width
    }

    pub fn height(&self) -> usize {
        self.height
    }
}

impl crate::TraitCapturer for Capturer {
    fn frame<'a>(&'a mut self, _timeout: Duration) -> io::Result<Frame<'a>> {
        {
            let mut latest = LATEST.lock().unwrap();
            // A size change is picked up by the display check, which recreates the capturer.
            if latest.seq == self.seq
                || latest.width != self.width
                || latest.height != self.height
            {
                return Err(io::ErrorKind::WouldBlock.into());
            }
            // Swap instead of copy, the pusher refills our old buffer next time.
            std::mem::swap(&mut self.data, &mut latest.data);
            self.stride = latest.stride;
            self.seq = latest.seq;
        }
        Ok(Frame::PixelBuffer(PixelBuffer {
            data: &self.data,
            width: self.width,
            height: self.height,
            stride: vec![self.stride],
        }))
    }
}

pub struct PixelBuffer<'a> {
    data: &'a [u8],
    width: usize,
    height: usize,
    stride: Vec<usize>,
}

impl<'a> crate::TraitPixelBuffer for PixelBuffer<'a> {
    fn data(&self) -> &[u8] {
        self.data
    }

    fn width(&self) -> usize {
        self.width
    }

    fn height(&self) -> usize {
        self.height
    }

    fn stride(&self) -> Vec<usize> {
        self.stride.clone()
    }

    fn pixfmt(&self) -> Pixfmt {
        Pixfmt::BGRA
    }
}

pub struct Display {
    width: usize,
    height: usize,
}

impl Display {
    pub fn primary() -> io::Result<Display> {
        let start = Instant::now();
        loop {
            let (width, height) = latest_size();
            if width > 0 && height > 0 {
                return Ok(Display { width, height });
            }
            if start.elapsed() >= FIRST_FRAME_WAIT {
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    "No screen frame from the broadcast yet",
                ));
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }

    pub fn all() -> io::Result<Vec<Display>> {
        Ok(vec![Display::primary()?])
    }

    pub fn width(&self) -> usize {
        self.width
    }

    pub fn height(&self) -> usize {
        self.height
    }

    pub fn origin(&self) -> (i32, i32) {
        (0, 0)
    }

    pub fn is_online(&self) -> bool {
        true
    }

    pub fn is_primary(&self) -> bool {
        true
    }

    pub fn name(&self) -> String {
        "iOS".into()
    }
}
