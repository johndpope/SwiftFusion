// Copyright 2020 The SwiftFusion Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ModelSupport
import SwiftFusion
import TensorFlow
import XCTest

final class ArrayImageTests: XCTestCase {
  func testCreateBlank() {
    let rows = 10
    let cols = 10
    let channels = 3
    let image = ArrayImage(rows: rows, cols: cols, channels: channels)
    for i in 0..<rows {
      for j in 0..<cols {
        for k in 0..<channels {
          XCTAssertEqual(image[i, j, k], 0)
        }
      }
    }
  }
}
