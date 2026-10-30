// SPDX-License-Identifier: MIT
//! The Rust side of kernoid's apps. Dart sees `api` (through flutter_rust_bridge, `frb_generated`); `client` speaks
//! JMAP with kernoid.

pub mod api;
pub mod client;
mod frb_generated;
