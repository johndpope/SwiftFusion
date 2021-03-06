import TensorFlow
import XCTest

import SwiftFusion

fileprivate func jacobian<A: Differentiable>(
  of f: @differentiable(A) -> Pose2,
  at p: A
) -> [A.TangentVector] {
  let pb = pullback(at: p, in: f)
  return Pose2.TangentVector.standardBasis.map { pb($0) }
}

final class Pose2Tests: XCTestCase {
  /// test between for trivial values
  func testBetweenIdentitiesTrivial() {
    let wT1 = Pose2(0, 0, 0), wT2 = Pose2(0, 0, 0)
    let expected = Pose2(0, 0, 0)
    let actual = between(wT1, wT2)
    XCTAssertEqual(actual, expected)
  }

  /// test between function for non-rotated poses
  func testBetweenIdentities() {
    let wT1 = Pose2(2, 1, 0), wT2 = Pose2(5, 2, 0)
    let expected = Pose2(3, 1, 0)
    let actual = between(wT1, wT2)
    XCTAssertEqual(actual, expected)
  }

  /// test between function for rotated poses
  func testBetweenIdentitiesRotated() {
    let wT1 = Pose2(1, 0, 3.1415926 / 2.0), wT2 = Pose2(1, 0, -3.1415926 / 2.0)
    let expected = Pose2(0, 0, -3.1415926)
    let actual = between(wT1, wT2)
    // dump(expected, name: "expected");
    // dump(actual, name: "actual");
    XCTAssertEqual(actual.rot.theta, expected.rot.theta, accuracy: 1e-6)
    XCTAssertEqual(actual.t, expected.t)
  }

  /// test the simplest compose (multiplication)
  func testCompose() {
    let pose1 = Pose2(Rot2(.pi/4.0), Vector2(sqrt(0.5), sqrt(0.5)))
    let pose2 = Pose2(Rot2(.pi/2.0), Vector2(0.0, 2.0))

    let actual = pose1 * pose2

    let expected = Pose2(Rot2(3.0 * .pi/4.0), Vector2(-sqrt(0.5), 3.0*sqrt(0.5)))
    
    let _ = expected.recursivelyAllKeyPaths(to: Double.self).map {
      XCTAssertEqual(expected[keyPath: $0], actual[keyPath: $0], accuracy: 1e-9)
    }
  }
  
  /// test the simplest compose (multiplication)
  func testInverse() {
    let gTl = Pose2(Rot2(.pi/2.0), Vector2(1.0, 2.0))

    let actual = gTl.inverse()

    let expected = Pose2(Rot2(-.pi/2.0), Vector2(-2, 1.0))
    
    let _ = expected.recursivelyAllKeyPaths(to: Double.self).map {
      XCTAssertEqual(expected[keyPath: $0], actual[keyPath: $0], accuracy: 1e-9)
    }
  }
  
  /// test the between function against GTSAM
  func testBetween() {
    let p1 = Pose2(1.23, 2.30, 0.2)
    let odo = Pose2(0.53, 0.39, 0.15)
    let p2 = p1 * odo
    
    let expected = between(p1, p2)
    let _ = expected.recursivelyAllKeyPaths(to: Double.self).map {
      XCTAssertEqual(expected[keyPath: $0], odo[keyPath: $0], accuracy: 1e-9)
    }
  }
  
  /// test the simplest gradient descent on Pose2
  func testBetweenDerivatives() {
    var pT1 = Pose2(Rot2(0), Vector2(1, 0)), pT2 = Pose2(Rot2(1), Vector2(1, 1))

    for _ in 0..<100 {
      let (_, 𝛁loss) = valueWithGradient(at: pT1) { pT1 -> Double in
        var loss: Double = 0
        let ŷ = between(pT1, pT2)
        let error = ŷ.rot.theta * ŷ.rot.theta + ŷ.t.x * ŷ.t.x + ŷ.t.y * ŷ.t.y
        loss = loss + (error / 10)

        return loss
      }

      // print("𝛁loss", 𝛁loss)
      pT1.move(along: -𝛁loss)
    }

    print("DONE.")
    print("pT1: \(pT1 as AnyObject), pT2: \(pT2 as AnyObject)")

    XCTAssertEqual(pT1.rot.theta, pT2.rot.theta, accuracy: 1e-5)
  }

  /// TODO(fan): Change this to a proper noise model
  @differentiable
  func e_pose2(_ ŷ: Pose2) -> Double {
    // Squared error with Gaussian variance as weights
    0.1 * ŷ.rot.theta * ŷ.rot.theta + 0.3 * ŷ.t.x * ŷ.t.x + 0.3 * ŷ.t.y * ŷ.t.y
  }

  /// test convergence for a simple Pose2SLAM
  func testPose2SLAM() {
    let dumpjson = { (p: Pose2) -> String in
      "[ \(p.t.x), \(p.t.y), \(p.rot.theta)]"
    }

    // Initial estimate for poses
    let p1T0 = Pose2(Rot2(0.2), Vector2(0.5, 0.0))
    let p2T0 = Pose2(Rot2(-0.2), Vector2(2.3, 0.1))
    let p3T0 = Pose2(Rot2(.pi / 2), Vector2(4.1, 0.1))
    let p4T0 = Pose2(Rot2(.pi), Vector2(4.0, 2.0))
    let p5T0 = Pose2(Rot2(-.pi / 2), Vector2(2.1, 2.1))

    var map = [p1T0, p2T0, p3T0, p4T0, p5T0]

    // print("map_history = [")
    for _ in 0..<400 {
      let (_, 𝛁loss) = valueWithGradient(at: map) { map -> Double in
        var loss: Double = 0

        // Odometry measurements
        let p2T1 = between(between(map[1], map[0]), Pose2(2.0, 0.0, 0.0))
        let p3T2 = between(between(map[2], map[1]), Pose2(2.0, 0.0, .pi / 2))
        let p4T3 = between(between(map[3], map[2]), Pose2(2.0, 0.0, .pi / 2))
        let p5T4 = between(between(map[4], map[3]), Pose2(2.0, 0.0, .pi / 2))

        // Sum through the errors
        let error = self.e_pose2(p2T1) + self.e_pose2(p3T2) + self.e_pose2(p4T3) + self.e_pose2(p5T4)
        loss = loss + (error / 3)

        return loss
      }

      // print("[")
      // for v in map.indices {
      //   print("\(dumpjson(map[v]))\({ () -> String in if v == map.indices.endIndex - 1 { return "" } else { return "," } }())")
      // }
      // print("],")

      // print("𝛁loss", 𝛁loss)
      // NOTE: this is more like sparse rep not matrix Jacobian
      for i in map.indices {
        map[i].move(along: -𝛁loss[i])
      }
    }

    // print("]")

    print("map = [")
    for v in map.indices {
      print("\(dumpjson(map[v]))\({ () -> String in if v == map.indices.endIndex - 1 { return "" } else { return "," } }())")
    }
    print("]")

    let p5T1 = between(map[4], map[0])

    // Test condition: P_5 should be identical to P_1 (close loop)
    XCTAssertEqual(p5T1.t.norm, 0.0, accuracy: 1e-1)
  }

  /// Tests that the manifold invariant holds for Pose2
  func testManifoldIdentity() {
    for _ in 0..<10 {
      let p = Pose2(randomWithCovariance: eye(rowCount: 3))
      let q = Pose2(randomWithCovariance: eye(rowCount: 3))
      let actual: Pose2 = Pose2(coordinate: p.coordinate.retract(p.coordinate.localCoordinate(q.coordinate)))
      assertAllKeyPathEqual(actual, q, accuracy: 1e-10)
    }
  }
  
  /// Tests that the Pose2 Expmap
  func testManifoldExpmap1() {
    let pose = Pose2(Rot2(.pi/2), Vector2(1, 2));
    let expected = Pose2(1.00811, 2.01528, 2.5608);
    let actual = Pose2(coordinate: pose.coordinate.retract(Vector3(0.99, 0.01, -0.015)))
    XCTAssertEqual(
      expected.rot.theta,
      actual.rot.theta,
      accuracy: 1e-5
    )
    XCTAssertEqual(
      expected.t.x,
      actual.t.x,
      accuracy: 1e-5
    )
    XCTAssertEqual(
      expected.t.y,
      actual.t.y,
      accuracy: 1e-5
    )
  }
  
  /// Tests the manifold Expmap
  func testManifoldExpmap2() {
//    let A = Tensor<Double>(shape: [3, 3], scalars: [
//        0.0,   0.0,  0.0,
//        0.01,  0.0, -0.99,
//        -0.015, 0.99,  0.0 ])
//    let A2 = matmul(A, A)/2.0, A3 = matmul(A2, A)/3.0, A4 = matmul(A3, A)/4.0
//    let expected = eye(rowCount: 3) + A + A2 + A3 + A4;
//
//    let v = Vector3(0.99, 0.01, -0.015);
//    let pose = Pose2(coordinate: Pose2(0, 0, 0).coordinate.retract(v))
//    let actual = pose.AdjointMatrix
    // assertEqual(actual, expected, accuracy: 1e-5)
    // TODO: This is also commented out in GTSAM, why?
  }
  
  /// Tests that the Pose2 Expmap
  func testManifoldExpmap0d() {
    let expected = Pose2(0, 0, 0);
    let actual = Pose2(coordinate: Pose2(0, 0, 0).coordinate.retract(Vector3(2 * .pi, 0, 2 * .pi)))
    XCTAssertEqual(
      expected.rot.theta,
      actual.rot.theta,
      accuracy: 1e-5
    )
    XCTAssertEqual(
      expected.t.x,
      actual.t.x,
      accuracy: 1e-5
    )
    XCTAssertEqual(
      expected.t.y,
      actual.t.y,
      accuracy: 1e-5
    )
  }
  
  /// Tests that the derivative of the identity function is correct at a few random points.
  func testDerivativeIdentity() {
    func identity(_ x: Pose2) -> Pose2 {
      Pose2(x.rot, x.t)
    }
    for _ in 0..<10 {
      let expected: Tensor<Double> = eye(rowCount: 3)
      assertEqual(
        Tensor<Double>(stacking: jacobian(
          of: identity,
          at: Pose2(randomWithCovariance: eye(rowCount: 3))).map { $0.flatTensor }),
        expected,
        accuracy: 1e-10
      )
    }
  }

  /// Test that the derivative of the group inverse operation is correct at a few random points.
  func testDerivativeInverse() {
    for _ in 0..<10 {
      let pose = Pose2(randomWithCovariance: eye(rowCount: 3))
      let expected = -pose.AdjointMatrix
      assertEqual(
        Tensor<Double>(stacking: jacobian(of: { $0.inverse() }, at: pose).map { $0.flatTensor }),
        expected,
        accuracy: 1e-10
      )
    }
  }

  /// Test the the derivative of the group operations is correct at a few random points.
  func testDerivativeMultiplication() {
    for _ in 0..<10 {
      let lhs = Pose2(randomWithCovariance: eye(rowCount: 3))
      let rhs = Pose2(randomWithCovariance: eye(rowCount: 3))
      let expectedWrtLhs = rhs.inverse().AdjointMatrix
      let expectedWrtRhs: Tensor<Double> = eye(rowCount: 3)
      assertEqual(
        Tensor<Double>(stacking: jacobian(of: { $0 * rhs }, at: lhs).map { $0.flatTensor }),
        expectedWrtLhs,
        accuracy: 1e-10
      )
      assertEqual(
        Tensor<Double>(stacking: jacobian(of: { lhs * $0 }, at: rhs).map { $0.flatTensor }),
        expectedWrtRhs,
        accuracy: 1e-10
      )
    }
  }

  /// tests a simple identity Jacobian for Pose2
  func testJacobianPose2Identity() {
    let wT1 = Pose2(1, 0, 3.1415926 / 2.0), wT2 = Pose2(1, 0, 3.1415926 / 2.0)
    let pts: [Pose2] = [wT1, wT2]

    let f: @differentiable(_ pts: [Pose2]) -> Vector1 = { (_ pts: [Pose2]) -> Vector1 in
      let d = between(pts[0], pts[1])

      return Vector1(d.rot.theta * d.rot.theta + d.t.x * d.t.x + d.t.y * d.t.y)
    }

    let pb = pullback(at: pts, in: f)
    let j = Vector1.TangentVector.standardBasis.map { pb($0) }
    // print("J(f) = \(j[0].base as AnyObject)")
    for item in j[0] {
      XCTAssertEqual(item, Pose2.TangentVector.zero)
    }
  }

  /// Tests the jacobian of the `between` function.
  func testJacobianPose2Trivial() {
    // Values taken from GTSAM `testPose2.cpp`
    let wT1 = Pose2(1, 2, .pi/2.0), wT2 = Pose2(-1, 4, .pi)

    // Note that these numbers are a permutation of the corresponding numbers from GTSAM because
    // the SwiftFusion convention for tangent vector is (omega, v) while the GTSAM convention is
    // (v, omega).
    let expectedWrtLhs = Tensor<Double>([
      [-1.0, 0.0,  0.0],
      [-2.0, 0.0, -1.0],
      [-2.0, 1.0,  0.0]
    ])
    let expectedWrtRhs = Tensor<Double>([
      [1.0, 0.0, 0.0],
      [0.0, 1.0, 0.0],
      [0.0, 0.0, 1.0]
    ])

    assertEqual(
      Tensor<Double>(stacking: jacobian(of: { between($0, wT2) }, at: wT1).map { $0.flatTensor }),
      expectedWrtLhs,
      accuracy: 1e-10
    )
    assertEqual(
      Tensor<Double>(stacking: jacobian(of: { between(wT1, $0) }, at: wT2).map { $0.flatTensor }),
      expectedWrtRhs,
      accuracy: 1e-10
    )
  }

  /// Tests that the custom implementations of `Adjoint` and `AdjointTranspose` are correct.
  func testAdjoint() {
    for _ in 0..<10 {
      let pose = Pose2(randomWithCovariance: eye(rowCount: 3))
      for v in Pose2.TangentVector.standardBasis {
        assertEqual(
          pose.Adjoint(v).flatTensor,
          pose.coordinate.defaultAdjoint(v).flatTensor,
          accuracy: 1e-10
        )
        assertEqual(
          pose.AdjointTranspose(v).flatTensor,
          pose.coordinate.defaultAdjointTranspose(v).flatTensor,
          accuracy: 1e-10
        )
      }
    }
  }
}
