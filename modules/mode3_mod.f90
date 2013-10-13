MODULE mode3_mod
USE bmad

REAL(rp), PARAMETER :: m = 0.707106781d0  ! 1/sqrt(2)
REAL(rp), PARAMETER :: o = 0.0d0  ! for compact code
REAL(rp), PARAMETER :: l = 1.0d0  ! for compact code

REAL(rp), PARAMETER :: Qr(6,6) = RESHAPE( [m,m,o,o,o,o, o,o,o,o,o,o, o,o,m,m,o,o,   &
                                           o,o,o,o,o,o, o,o,o,o,m,m, o,o,o,o,o,o],[6,6] )
REAL(rp), PARAMETER :: Qi(6,6) = RESHAPE( [o,o,o,o,o,o, m,-m,o,o,o,o, o,o,o,o,o,o,  &
                                           o,o,m,-m,o,o, o,o,o,o,o,o, o,o,o,o,m,-m],[6,6] )
REAL(rp), PARAMETER :: Qinv_r(6,6) = RESHAPE( [m,o,o,o,o,o, m,o,o,o,o,o, o,o,m,o,o,o,  &
                                               o,o,m,o,o,o, o,o,o,o,m,o, o,o,o,o,m,o],[6,6] )
REAL(rp), PARAMETER :: Qinv_i(6,6) = RESHAPE( [o,-m,o,o,o,o, o,m,o,o,o,o, o,o,o,-m,o,o,  &
                                               o,o,o,m,o,o, o,o,o,o,o,-m, o,o,o,o,o,m],[6,6] )
REAL(rp), PARAMETER :: S(6,6) = RESHAPE( [o,-l,o,o,o,o, l,o,o,o,o,o,  &
                                          o,o,o,-l,o,o, o,o,l,o,o,o,  &
                                          o,o,o,o,o,-l, o,o,o,o,l,o],[6,6] )
REAL(rp), PARAMETER :: I2(2,2) = RESHAPE( [1,0, 0,1],[2,2] )

PRIVATE m, o, l
PRIVATE Qr, Qi
PRIVATE Qinv_r, Qinv_i
PRIVATE S

CONTAINS

!+
! Subroutine normal_mode3_calc (mat, tune, G, V, synchrotron_motion)
!
! Does an Eigen decomposition of the 1-turn transfer matrix (mat) and generates
! B, V, H.  Betatron and synchrotron tunes are places in tune.
!
! Input:
!  mat(6,6)            -- real(rp): 1-turn transfer matrix
!  synchrotron_motion  -- real(rp), optional: Default is to treat tune(3) as if it were a synchrotron tune:
!                                             tune(3) = 2pi - tune(3).  IF present and true, then this
!                                             correction is overridden.
! Output:
!  tune(3)             -- real(rp): Tunes of the 3 normal modes (radians)
!  B(6,6)              -- real(rp): B is block diagonal and related to the normal mode Twiss parameters.
!  HV(6,6)             -- real(rp): Transforms from normal mode coordinates to canonical coordinates: x = H.V.a
!
!-
SUBROUTINE normal_mode3_calc (mat, tune, B, HV, synchrotron_motion)
  USE bmad

  IMPLICIT NONE

  REAL(rp) mat(6,6)
  REAL(rp) tune(3)
  REAL(rp) B(6,6)
  REAL(rp) V(6,6)
  REAL(rp) H(6,6)
  REAL(rp) HV(6,6)
  LOGICAL, OPTIONAL :: synchrotron_motion

  REAL(rp) N(6,6)

  LOGICAL error

  CALL make_N(mat, N, error, tune, synchrotron_motion)
  CALL make_HVBP (N, B, V, H)
  HV = MATMUL(H,V)

END SUBROUTINE normal_mode3_calc

!+
! Subroutine make_HVBP(N, B, V, H, Vbar, Hbar)
!
! Parameterizes the eigen-decomposition of the 6x6 transfer matrix into HVBP as defined in:
! "From the beam-envelop matrix to synchrotron-radiation integrals" by Ohmi, Hirata, and Oide.
!
! M = N.U.Inverse[N] where U is block diagonal and the blocks are 2x2 rotation matrices.
! N = H.V.B.P
! P has the same free parameters as B
! B "Twiss matrix" has 6 free parameters (Twiss alphas and betas)
! B blocks have the form /    sqrt(beta)         0       \
!                        \ alpha/sqrt(beta) 1/sqrt(beta) /
! V "Teng matrix" has 4 free parameters (xy, xpy, ypx, and pxpy coupling)
! H "Dispersion matrix" has 8 free parameters (xz, xpz, pxz, pxpz, yz, ypz, pyz, pypz coupling)
! 
!
! Input:
!  N(6,6)              -- real(rp): Matrix of eigenvectors prepared by make_N
!
! Output:
!  B(6,6)              -- real(rp): Block diagonal matrix of Twiss parameters
!  V(6,6)              -- real(rp): horizontal-vertical coupling information
!  H(6,6)              -- real(rp): horizontal-longitudinal and vertical-longitudinal coupling information
!  Vbar(6,6)           -- real(rp), optional: dagger(B).V.B
!  Hbar(6,6)           -- real(rp), optional: dagger(B).H.B
!
!-
SUBROUTINE make_HVBP (N, B, V, H, Vbar, Hbar)
  USE bmad

  IMPLICIT NONE

  REAL(rp) N(6,6)
  REAL(rp) B(6,6)
  REAL(rp) R(6,6)
  REAL(rp) H(6,6)
  REAL(rp), OPTIONAL :: Vbar(6,6)
  REAL(rp), OPTIONAL :: Hbar(6,6)

  INTEGER i

  ! Note: the variables are named here to according to the convention in the above mentioned paper.
  REAL(rp) V(6,6)
  REAL(rp) a, ax, ay
  REAL(rp) BcPc(2,2)
  REAL(rp) Hx(2,2)
  REAL(rp) Hy(2,2)
  REAL(rp) VBP(6,6)
  REAL(rp) mu
  REAL(rp) BbPb(2,2)
  REAL(rp) BaPa(2,2)
  REAL(rp) V2(2,2)
  REAL(rp) BP(6,6)
  REAL(rp) cospa, sinpa
  REAL(rp) cospb, sinpb
  REAL(rp) cospc, sinpc
  REAL(rp) Pinv(6,6)

  a = SQRT(ABS(determinant(N(5:6,5:6))))
  BcPc = N(5:6,5:6) / a
  Hx = MATMUL(N(1:2,5:6),dagger2(BcPc))
  Hy = MATMUL(N(3:4,5:6),dagger2(BcPc))
  ax = determinant(Hx)/(1.0d0+a)  !shorthand
  ay = determinant(Hy)/(1.0d0+a)  !shorthand

  H(1:2,1:2) = (1.0d0-ax)*I2
  H(3:4,3:4) = (1.0d0-ay)*I2
  H(5:6,5:6) = a*I2
  H(1:2,5:6) = Hx
  H(3:4,5:6) = Hy
  H(5:6,1:2) = -1.0d0*dagger2(Hx)
  H(5:6,3:4) = -1.0d0*dagger2(Hy)
  H(1:2,3:4) = -1.0d0 * MATMUL(Hx,dagger2(Hy)) / (1.0d0 + a)
  H(3:4,1:2) = -1.0d0 * MATMUL(Hy,dagger2(Hx)) / (1.0d0 + a)

  VBP = MATMUL(dagger6(H),N)

  mu = SQRT(ABS(determinant(VBP(1:2,1:2))))
  BaPa = VBP(1:2,1:2)/mu
  BbPb = VBP(3:4,3:4)/mu
  V2 = MATMUL(VBP(1:2,3:4),dagger2(BbPb))

  V = 0.0d0
  V(1:2,1:2) = mu*I2
  V(3:4,3:4) = mu*I2
  V(5:6,5:6) = I2
  V(1:2,3:4) = V2
  V(3:4,1:2) = -1.0d0*dagger2(V2)

  BP = 0.0d0
  BP(1:2,1:2) = BaPa
  BP(3:4,3:4) = BbPb
  BP(5:6,5:6) = BcPc

  !- The following convention for P, puts B (the Twiss matrix) into the form where the upper right element is zero.
  cospa = 1.0d0 / SQRT(1.0d0 + (BP(1,2)/BP(1,1))**2)
  sinpa = 1.0d0 * BP(1,2) / BP(1,1) * cospa
  cospb = 1.0d0 / SQRT(1.0d0 + (BP(3,4)/BP(3,3))**2)
  sinpb = 1.0d0 * BP(3,4) / BP(3,3) * cospb
  cospc = 1.0d0 / SQRT(1.0d0 + (BP(5,6)/BP(5,5))**2)
  sinpc = 1.0d0 * BP(5,6) / BP(5,5) * cospc
  Pinv = 0.0d0
  Pinv(1,1) = cospa
  Pinv(2,2) = cospa
  Pinv(1,2) = -1.0d0 * sinpa
  Pinv(2,1) = sinpa
  Pinv(3,3) = cospb
  Pinv(4,4) = cospb
  Pinv(3,4) = -1.0d0 * sinpb
  Pinv(4,3) = sinpb
  Pinv(5,5) = cospc
  Pinv(6,6) = cospc
  Pinv(5,6) = -1.0d0 * sinpc
  Pinv(6,5) = sinpc

  B = MATMUL(BP,Pinv)

  IF( PRESENT(Vbar) ) Vbar = MATMUL(dagger6(B),MATMUL(V,B))
  IF( PRESENT(Hbar) ) Hbar = MATMUL(dagger6(B),MATMUL(H,B))
END SUBROUTINE make_HVBP

!+
! Subroutine xyz_to_action(ring,ix,X,J,error)
!
! Given the canonical phase space coordinates X of a particle, this returns
! a vector from which Ja, Jb, Jc can be easily extracted.
!
! The J vector looks like:
! J = (sqrt(2Ja)cos(phia), -sqrt(2Ja)sin(phia), sqrt(2Jb)cos(phib), -sqrt(2Jb)sin(phib), sqrt(2Jc)cos(phic), -sqrt(2Jc)sin(phic))
!
! J is obtained from:
! J = N_inv . X
! Where N_inv is from the Eigen decomposition of the 1-turn transfer matrix.
!
! The normal mode invariant actions can be obtained from J as,
! Ja = (J(1)**2 + J(2)**2)/2.0d0
! Jb = (J(3)**2 + J(4)**2)/2.0d0
! Jc = (J(5)**2 + J(6)**2)/2.0d0
!
! Input:
!  ring     -- lat_struct: lattice
!  ix       -- integer: element index at which to calculate J
!  X(1:6)   -- real(rp): canonical phase space coordinates of the particle
!
! Output:
!  J(1:6)   -- real(rp): Vector containing normal mode invariants and phases
!  error    -- logical: Set to true on error.  Often means Eigen decomposition failed.
!
!-
SUBROUTINE xyz_to_action(ring,ix,X,J,error)
  USE bmad

  IMPLICIT none

  TYPE(lat_struct) ring
  INTEGER ix
  REAL(rp) J(1:6)
  REAL(rp) X(1:6)
  REAL(rp) t6(1:6,1:6)
  REAL(rp) N(1:6,1:6)
  LOGICAL error

  CALL transfer_matrix_calc (ring, .true., t6, ix1=ix, one_turn=.true.)
  CALL make_N(t6, N, error)
  IF( error ) THEN
    RETURN
  ENDIF

  J = MATMUL(dagger6(N),X)
END SUBROUTINE xyz_to_action

!+
! Subroutine action_to_xyz(ring,ix,J,X,error)
!
! Given the normal mode invariants and phases J of a particle, returns the canonical coordinates.
!
! The J vector looks like:
! J = (sqrt(2Ja)cos(phia), -sqrt(2Ja)sin(phia), sqrt(2Jb)cos(phib), -sqrt(2Jb)sin(phib), sqrt(2Jc)cos(phic), -sqrt(2Jc)sin(phic))
!
! X is obtained from:
! X = N . J
! Where N is from the Eigen decomposition of the 1-turn transfer matrix.
!
! Input:
!  ring     -- lat_struct: lattice
!  ix       -- integer: element index at which to calculate J
!  J(1:6)   -- real(rp): Vector containing normal mode invariants and phases
!
! Output:
!  X(1:6)   -- real(rp): canonical phase space coordinates of the particle
!  error    -- logical: Set to true on error.  Often means Eigen decomposition failed.
!
!-
SUBROUTINE action_to_xyz(ring,ix,J,X,error)
  USE bmad
  USE eigen_mod

  IMPLICIT none

  TYPE(lat_struct) ring
  INTEGER ix
  REAL(rp) J(1:6)
  REAL(rp) X(1:6)
  REAL(rp) t6(1:6,1:6)
  REAL(rp) N(1:6,1:6)
  REAL(rp) Ninv(1:6,1:6)
  REAL(rp) gamma(3)

  INTEGER i

  LOGICAL error

  CALL transfer_matrix_calc (ring, .true., t6, ix1=ix, one_turn=.true.)
  CALL make_N(t6, N, error)
  IF( error ) THEN
    RETURN
  ENDIF

  X = MATMUL(N,J)
END SUBROUTINE action_to_xyz

!+
! Subroutine make_N(t6,N,error,tunes,synchrotron_motion)
!
! Given a 1-turn transfer matrix, this returns N and its inverse Ninv.
! N converts between normal invarients and phases and canonical coordinates:
! X = N.J
!
! N is obtained from the Eigen decomposition of the 1-turn transfer matrix.
! It is obtained by applying certain normalizations to the matrix of Eigen vectors, then making
! the result real using Q.
!
! Input:
!  t6(6,6)             -- real(rp): 1-turn transfer matrix
!  synchrotron_motion  -- real(rp), optional: Default is to treat tune(3) as if it were a synchrotron tune:
!                                             tune(3) = tune(3) - 2pi.  IF present and true, then this
!                                             correction is overridden.
! Output:
!  N(6,6)              -- real(rp): X = N.J
!  Ninv(6,6)           -- real(rp): J = Ninv.X
!  error               -- logical: Set to true on error.  Often means Eigen decomposition failed.
!  gamma(3)            -- real(rp): gamma1, gamma2, and gamma3, related to calculation of G
!  tunes(3)            -- real(rp): Tune of the 3 normal modes of the beam (radians)
!-
SUBROUTINE make_N(t6,N,error,tunes,synchrotron_motion)
  USE bmad
  USE eigen_mod

  IMPLICIT NONE

  REAL(rp) t6(6,6)
  REAL(rp) eval_r(6), eval_i(6)
  REAL(rp) evec_r(6,6), evec_i(6,6)
  REAL(rp) N(6,6)
  REAL(rp) Lambda(6,6)
  REAL(rp), OPTIONAL :: tunes(3)
  LOGICAL, OPTIONAL :: synchrotron_motion

  LOGICAL error

  INTEGER i

  CALL mat_eigen (t6, eval_r, eval_i, evec_r, evec_i, error)
  evec_r = TRANSPOSE(evec_r)
  evec_i = TRANSPOSE(evec_i)

  IF( error ) THEN
    RETURN
  ENDIF

  CALL real_and_symp(evec_r, evec_i, eval_r, eval_i, N, Lambda)

  IF( PRESENT(tunes) ) THEN
    tunes(1) = MyTan(Lambda(1,2), Lambda(1,1))
    tunes(2) = MyTan(Lambda(3,4), Lambda(3,3))
    tunes(3) = MyTan(Lambda(5,6), Lambda(5,5)) - twopi
  ENDIF
  IF( PRESENT(tunes) .and. PRESENT(synchrotron_motion) ) THEN
    IF ( .NOT. synchrotron_motion) tunes(3) = tunes(3) + twopi
  ENDIF

  CONTAINS

    FUNCTION MyTan(y,x) RESULT(arg)
      !For a complex number x+iy graphed on an xhat,yhat plane, this routine returns the angle
      !between (x,y) and the +x axis, measured counter-clockwise.  There is a branch cut along +x.
      !This routine returns a number between 0 and 2pi.
      REAL(rp) x,y,arg

      IF(y .GE. 0) THEN
        arg = ATAN2(y,x)
      ELSE
        arg = ATAN2(y,x) + 2.0d0*pi
      ENDIF
    END FUNCTION MyTan
END SUBROUTINE make_N

!+
! Subroutine normal_sigma_mat(sigma_mat,normal)
!
! Given a beam envelop sigma matrix sigma_mat, this returns the 3 normal mode
! emittances.
!
! The normal mode emittance of the sigma matrix are the eigenvalues of
! sigma_mat . S
!
!     / 0  1  0  0  0  0 \
!     |-1  0  0  0  0  0 |
! S = | 0  0  0  1  0  0 |
!     | 0  0 -1  0  0  0 |
!     | 0  0  0  0  0  1 |
!     \ 0  0  0  0 -1  0 /
!
! Input:
!  sigma_mat(6,6)   -- real(rp): beam envelop sigma matrix
! Output:
!  normal(3)        -- real(rp): normal mode emittances
!-
SUBROUTINE normal_sigma_mat(sigma_mat,normal)
  USE bmad
  USE eigen_mod

  IMPLICIT none

  REAL(rp) sigma_mat(1:6,1:6)
  REAL(rp) normal(1:3)
  REAL(rp) eval_r(1:6), eval_i(1:6)
  REAL(rp) evec_r(1:6,1:6), evec_i(1:6,1:6)
  REAL(rp) sigmaS(1:6,1:6)

  LOGICAL error

  sigmaS = MATMUL(sigma_mat,S)

  CALL mat_eigen(sigmaS,eval_r,eval_i,evec_r,evec_i,error)

  normal(1) = ABS(eval_i(1))
  normal(2) = ABS(eval_i(3))
  normal(3) = ABS(eval_i(5))
END SUBROUTINE normal_sigma_mat

!+
! Subrouting get_abc_from_updated_smat(ring, ix, sigma_mat, normal, error)
!
! This subroutine is experimental.  It obtains the normal mode emittances from the sigma matrix using the 
! eigenvectors of the 1-turn transfer matrix.  It is used to obtain the emittances from a sigma matrix
! that has been perturbed.  Under ordinary circumstances, the eigenvectors of the sigma matrix and 1-turn matrix
! should be the same.  However, if the sigma matrix has been perturbed, then they may not be the same.  The question
! is then:  Are the normal mode emittances the eigenvalues of the sigma matrix? Or should the eigenvectors
! of the 1-turn matrix be applied to the sigmatrix, and the values of the resulting almost-diagonal matrix
! taken as the emittance?  Or maybe the emittance is not well-defined if the sigma-matrix is perturbed.
!
! Input:
!  ring           -- lat_struct: the ring
!  ix             -- integer: element at which to do the transformation
!  sigma_mat(6,6) -- real(rp): beam envelop sigma matrix (possibly perturbed)
! Output:
!  normal(3)      -- real(rp): something like the normal mode emittances of the sigma matrix
!  error          -- logical:  set to true if something goes wrong.  Usually means Eigen decomposition of the 1-turn matrix failed.
!-
SUBROUTINE get_abc_from_updated_smat(ring, ix, sigma_mat, normal, error)

  USE bmad
  USE eigen_mod

  TYPE(lat_struct) ring
  INTEGER ix
  REAL(rp) normal(3)
  REAL(rp) sigma_mat(6,6)

  REAL(rp) eval_r(6)
  REAL(rp) eval_i(6)
  REAL(rp) evec_r(6,6)
  REAL(rp) evec_i(6,6)
  REAL(rp) evec_inv_r(6,6)
  REAL(rp) evec_inv_i(6,6)
  REAL(rp) t6(6,6)
  REAL(rp) smatS(6,6)

  REAL(rp) term3(6,6)
  REAL(rp) term4(6,6)
  REAL(rp) termSum(6,6)
  REAL(rp) Lambda(6,6)
  REAL(rp) N(6,6)

  LOGICAL ok, error
  INTEGER i

  error = .false.

  CALL transfer_matrix_calc (ring, .true., t6, ix1=ix, one_turn=.true.)

  CALL mat_eigen (t6, eval_r, eval_i, evec_r, evec_i, error)
  IF( error ) THEN
    WRITE(*,'(A,I6,A)') "BAD: Eigenvectors of transfer matrix not found for element ", ix, ring%ele(ix)%name
    RETURN
  ENDIF

  evec_r = TRANSPOSE(evec_r)
  evec_i = TRANSPOSE(evec_i)
  CALL real_and_symp(evec_r, evec_i, eval_r, eval_i, N, Lambda)
  CALL cplx_symp_conj(evec_r, evec_i, evec_inv_r, evec_inv_i)

  smatS = MATMUL(sigma_mat,S)

  term3 = MATMUL(evec_inv_r,MATMUL(smatS,evec_i))
  term4 = MATMUL(evec_inv_i,MATMUL(smatS,evec_r))
  termSum = term3+term4

  normal(1) = termSum(2,2)
  normal(2) = termSum(4,4)
  normal(3) = termSum(6,6)

END SUBROUTINE get_abc_from_updated_smat

!+
! Subroutine make_smat_from_abc(t6, mode, sigma_mat, error)
!
! Given the 1-turn transfer matrix and a normal_modes_struct containing the normal mode
! emittances, this routine returns the beam envelop sigma matrix.
!
! sigma_mat.S = N.D.dagger(N)
!
! Input:
!  t6(6,6)          -- real(rp): 1-turn transfer matrix
!  mode             -- normal_modes_struct: normal mode emittances
!      %a%emittance -- real(rp): a-mode emittance
!      %b%emittance -- real(rp): b-mode emittance
!      %z%emittance -- real(rp): z-mode emittance
! Output:
!  sigma_mat(6,6)   -- real(rp): beam envelop sigma matrix
!  error            -- logical:  set to true if something goes wrong.  Usually means Eigen decomposition of the 1-turn matrix failed.
!-
SUBROUTINE make_smat_from_abc(t6, mode, sigma_mat, error)

  USE bmad
  USE eigen_mod

  REAL(rp) t6(6,6)
  TYPE(normal_modes_struct) mode
  REAL(rp) sigma_mat(6,6)
  LOGICAL error

  REAL(rp) N(6,6)
  REAL(rp) D(6,6)
  REAL(rp) Lambda(6,6)

  INTEGER i

  error = .false.

  CALL make_N(t6, N, error)
  IF( error ) THEN
    WRITE(*,'(A,I6,A)') "BAD: Eigenvectors of transfer matrix not found for element."
    RETURN
  ENDIF

  D = 0.0d0
  D(1,2) =  mode%a%emittance
  D(2,1) = -mode%a%emittance
  D(3,4) =  mode%b%emittance
  D(4,3) = -mode%b%emittance
  D(5,6) =  mode%z%emittance
  D(6,5) = -mode%z%emittance

  sigma_mat = MATMUL( MATMUL( MATMUL(N,D),dagger6(N) ),dagger6(S) )
END SUBROUTINE make_smat_from_abc

!+
!
! Subroutine cplx_symp_conj(evec_r, evec_i, symp_evec_r, symp_evec_i)
!
! Return the complex symplectic conjugate of a 6x6 matrix.
! This is useful because if the input matrix is symplectic with respect to S, then the complex symplectic conjugate
! is the matrix inverse.
!
! This is much more robust and accurate than calculating the inverse by back substitution.
!
! Input:
!  evec_r(6,6)      -- real(rp): real part of input matrix
!  evec_i(6,6)      -- real(rp): imaginary part of input matrix
! Output:
!  symp_evec_r(6,6) -- real(rp): real part of the symplectic complex conjugate of the input matrix
!  symp_evec_i(6,6) -- real(rp): imaginary part of the symplectic complex conjugate of the input matrix
!
!-
SUBROUTINE cplx_symp_conj(evec_r, evec_i, symp_evec_r, symp_evec_i)

  USE bmad

  IMPLICIT NONE

  REAL(rp) evec_r(6,6)
  REAL(rp) evec_i(6,6)
  REAL(rp) symp_evec_r(6,6)
  REAL(rp) symp_evec_i(6,6)

  symp_evec_r(1:2,1:2) = dagger2(evec_i(1:2,1:2))
  symp_evec_r(1:2,3:4) = dagger2(evec_i(3:4,1:2))
  symp_evec_r(1:2,5:6) = dagger2(evec_i(5:6,1:2))
  symp_evec_r(3:4,1:2) = dagger2(evec_i(1:2,3:4))
  symp_evec_r(3:4,3:4) = dagger2(evec_i(3:4,3:4))
  symp_evec_r(3:4,5:6) = dagger2(evec_i(5:6,3:4))
  symp_evec_r(5:6,1:2) = dagger2(evec_i(1:2,5:6))
  symp_evec_r(5:6,3:4) = dagger2(evec_i(3:4,5:6))
  symp_evec_r(5:6,5:6) = dagger2(evec_i(5:6,5:6))

  symp_evec_i(1:2,1:2) = -dagger2(evec_r(1:2,1:2))
  symp_evec_i(1:2,3:4) = -dagger2(evec_r(3:4,1:2))
  symp_evec_i(1:2,5:6) = -dagger2(evec_r(5:6,1:2))
  symp_evec_i(3:4,1:2) = -dagger2(evec_r(1:2,3:4))
  symp_evec_i(3:4,3:4) = -dagger2(evec_r(3:4,3:4))
  symp_evec_i(3:4,5:6) = -dagger2(evec_r(5:6,3:4))
  symp_evec_i(5:6,1:2) = -dagger2(evec_r(1:2,5:6))
  symp_evec_i(5:6,3:4) = -dagger2(evec_r(3:4,5:6))
  symp_evec_i(5:6,5:6) = -dagger2(evec_r(5:6,5:6))
END SUBROUTINE cplx_symp_conj

!+
! Function dagger6(A) RESULT(Ad)
!
! Return the complex symplectic conjugate of a 6x6 matrix.
!
! A_dagger = -S.Transpose(A).S
!
! Input:
!  A(6,6)   -- real(rp): 6x6 matrix
! Output:
!  Ad(6,6)  -- real(rp): A_dagger
!-
FUNCTION dagger6(A) RESULT(Ad)
  USE bmad

  REAL(rp) A(6,6)
  REAL(rp) Ad(6,6)

  Ad = -1.0_rp * MATMUL(S,MATMUL(TRANSPOSE(A),S))
END FUNCTION dagger6

!+
! Function dagger2(A) RESULT(Ad)
!
! Return the complex symplectic conjugate of a 2x2 matrix.
!
! A_dagger = / A22  -A12 \
!            \ -A21  A11 /
!
! Input:
!  A(2,2)   -- real(rp): 2x2 matrix
! Output:
!  Ad(2,2)  -- real(rp): A_dagger
!-
FUNCTION dagger2(A) RESULT(Ad)
  USE bmad

  REAL(rp) A(2,2)
  REAL(rp) Ad(2,2)

  Ad(1,1) =  A(2,2)
  Ad(1,2) = -A(1,2)
  Ad(2,1) = -A(2,1)
  Ad(2,2) =  A(1,1)
END FUNCTION dagger2

!+
! Subroutine adjust_evec_phase(evec_r, evec_i, adj_evec_r, adj_evec_i)
!
! This subroutine assumes that the eigenvectors are arranged in complex-conjugate pairs: (e1 e1* e2 e2* e3 e3*)
!
! The following normalizations are applied to the matrix of eigenvectors.  The result is still a matrix of eigenvectors,
! but it is normalized and the phase adjusted such that G and V can be easily extracted.
! The resulting matrix of eigenvectors is unique
!
! 1) Swap columns to make determinant of diagonal blocks have positive imaginary part.
! 2) Adjust the phase of the eigenvectors such that the (1,1 and 1,2) and (3,3 and 3,4) and (5,5 and 5,6) elements are real.
! 3) Fixes the sign of the pairs so that the 1,1 3,3 and 5,5 elements are positive.
!
! Input:
!  evec_r(6,6)      -- real(rp): real part of Eigen matrix
!  evec_i(6,6)      -- real(rp): imaginary part of Eigen matrix
!  tunes(3)         -- real(rp): Tunes of the 3 normal modes.
! Output:
!  adj_evec_r(6,6)  -- real(rp): real part of Eigen matrix: normalized, phased, and signs fixed
!  adj_evec_i(6,6)  -- real(rp): imaginary part of Eigen matrix: normalized, phased, and signs fixed
!  tunes(3)         -- real(rp): Tunes of the 3 normal modes.  The ambiguity in tune is resolved so that det(G) = 1.
!
!-
SUBROUTINE adjust_evec_phase(evec_r, evec_i, adj_evec_r, adj_evec_i)
  REAL(rp) evec_r(6,6)
  REAL(rp) evec_i(6,6)
  REAL(rp) adj_evec_r(6,6)
  REAL(rp) adj_evec_i(6,6)
  REAL(rp) evec_r_temp(6)
  REAL(rp) evec_i_temp(6)

  REAL(rp) theta  
  REAL(rp) costh, sinth
  REAL(rp) det(3)

  INTEGER i, j, ix

  det(1) = AIMAG( CMPLX(evec_r(1,1),evec_i(1,1))*CMPLX(evec_r(2,2),evec_i(2,2)) - &
                CMPLX(evec_r(1,2),evec_i(1,2))*CMPLX(evec_r(2,1),evec_i(2,1)) )
  det(2) = AIMAG( CMPLX(evec_r(3,3),evec_i(3,3))*CMPLX(evec_r(4,4),evec_i(4,4)) - &
                CMPLX(evec_r(3,4),evec_i(3,4))*CMPLX(evec_r(4,3),evec_i(4,3)) )
  det(3) = AIMAG( CMPLX(evec_r(5,5),evec_i(5,5))*CMPLX(evec_r(6,6),evec_i(6,6)) - &
                CMPLX(evec_r(5,6),evec_i(5,6))*CMPLX(evec_r(6,5),evec_i(6,5)) )

  DO i=1,3
    ix = i*2-1
    IF( det(i) < 0 ) THEN
      evec_r_temp = evec_r(:,ix+1)
      evec_i_temp = evec_i(:,ix+1)
      evec_r(:,ix+1) = evec_r(:,ix)
      evec_i(:,ix+1) = evec_i(:,ix)
      evec_r(:,ix) = evec_r_temp
      evec_i(:,ix) = evec_i_temp
    ENDIF
  ENDDO

  DO i=1,3
    ix = i*2-1

    ! For each element of the eigenvector, rotate the eigenvector in the complex plane
    ! by an angle that makes the (1,1 and 1,2) or (3,3 and 3,4) or (5,5 and 5,6) elements of the eigen matrix real.
    theta = ATAN2(evec_i(ix,ix),evec_r(ix,ix)) 

    ! Apply the normalization and rotation
    costh = COS(theta)
    sinth = SIN(theta)
    adj_evec_r(:,ix) = ( evec_r(:,ix)*costh + evec_i(:,ix)*sinth)
    adj_evec_i(:,ix) = (-evec_r(:,ix)*sinth + evec_i(:,ix)*costh)

    adj_evec_r(:,ix+1) = ( evec_r(:,ix+1)*costh - evec_i(:,ix+1)*sinth)
    adj_evec_i(:,ix+1) = ( evec_r(:,ix+1)*sinth + evec_i(:,ix+1)*costh)
  ENDDO

END SUBROUTINE adjust_evec_phase

!+
! Subroutine real_and_symp(evec_r, evec_i, eval_r, eval_i, N, Lambda)
!
! Applies a normalization to the columns of a 6x6 matrix of eigenvectors, where the columns are complex
! conjugate pairs.  The normalization is such that the sum of the determinants of the 2x2 blocks down each pair of rows is 1.  
! The resulting matrix is symplectic with respect to S,
!  tr(N).S.N = S
!
! Input:
!  evec_r(6,6)      -- real(rp): real part of Eigen matrix
!  evec_i(6,6)      -- real(rp): imaginary part of Eigen matrix
!  eval_r(6)        -- real(rp): real part of eigen vectors.
!  eval_i(6)        -- real(rp): imaginary part of Eigen vectors.
! Output:
!  N(6,6)           -- real(rp): matrix of eigenvectors in real form.  Normalized symplectic.
!  Lambda(6,6)      -- real(rp): matrix of eigenvalues in block diagonal form.  Normalized symplectic.
!-
SUBROUTINE real_and_symp(evec_r, evec_i, eval_r, eval_i, N, Lambda)

  USE bmad

  IMPLICIT NONE

  REAL(rp) evec_r(6,6)
  REAL(rp) evec_i(6,6)
  REAL(rp) eval_r(6)
  REAL(rp) eval_i(6)
  REAL(rp) norm
  REAL(rp) check_mat(6,6)
  REAL(rp) N(6,6)
  REAL(rp) Lambda(6,6)
  INTEGER pair1(1), pair2(1), pair3(1), pairIndexes(6)
  INTEGER i

  check_mat = MATMUL(MATMUL(TRANSPOSE(evec_r),S),evec_i) + MATMUL(MATMUL(TRANSPOSE(evec_i),S),evec_r)
  IF( check_mat(1,2) < 0.0 ) THEN
    CALL swap(evec_r(:,1),evec_r(:,2))
    CALL swap(evec_i(:,1),evec_i(:,2))
    CALL swap(eval_r(1),eval_r(2))
    CALL swap(eval_i(1),eval_i(2))
  ENDIF
  IF( check_mat(3,4) < 0.0 ) THEN
    CALL swap(evec_r(:,3),evec_r(:,4))
    CALL swap(evec_i(:,3),evec_i(:,4))
    CALL swap(eval_r(3),eval_r(4))
    CALL swap(eval_i(3),eval_i(4))
  ENDIF
  IF( check_mat(5,6) < 0.0 ) THEN
    CALL swap(evec_r(:,5),evec_r(:,6))
    CALL swap(evec_i(:,5),evec_i(:,6))
    CALL swap(eval_r(5),eval_r(6))
    CALL swap(eval_i(5),eval_i(6))
  ENDIF

  !Transform to real basis
  N = MATMUL(evec_r,Qr) - MATMUL(evec_i,Qi)
  Lambda = 0.0d0
  Lambda(1,1) =  eval_r(1)
  Lambda(2,2) =  eval_r(1)
  Lambda(1,2) = -eval_i(1)
  Lambda(2,1) =  eval_i(1)
  Lambda(3,3) =  eval_r(3)
  Lambda(4,4) =  eval_r(3)
  Lambda(3,4) = -eval_i(3)
  Lambda(4,3) =  eval_i(3)
  Lambda(5,5) =  eval_r(5)
  Lambda(6,6) =  eval_r(5)
  Lambda(5,6) = -eval_i(5)
  Lambda(6,5) =  eval_i(5)

  !Normalize to make symplectic
  DO i=1,5,2
    norm = ABS(determinant(N(1:2,1:2)) + determinant(N(3:4,1:2)) + determinant(N(5:6,1:2)))
    N(:,1:2) = N(:,1:2)/SQRT(norm)
    norm = ABS(determinant(N(1:2,3:4)) + determinant(N(3:4,3:4)) + determinant(N(5:6,3:4)))
    N(:,3:4) = N(:,3:4)/SQRT(norm)
    norm = ABS(determinant(N(1:2,5:6)) + determinant(N(3:4,5:6)) + determinant(N(5:6,5:6)))
    N(:,5:6) = N(:,5:6)/SQRT(norm)
  ENDDO

  !Order eigenvector pairs
  pair1 = MAXLOC( [ N(1,1)**2+N(1,2)**2, N(1,3)**2+N(1,4)**2, N(1,5)**2+N(1,6)**2 ] )
  pair2 = MAXLOC( [ N(3,1)**2+N(3,2)**2, N(3,3)**2+N(3,4)**2, N(3,5)**2+N(3,6)**2 ] )
  pair3 = MAXLOC( [ N(5,1)**2+N(5,2)**2, N(5,3)**2+N(5,4)**2, N(5,5)**2+N(5,6)**2 ] )
  pairIndexes = [ 2*pair1(1)-1, 2*pair1(1), 2*pair2(1)-1, 2*pair2(1), 2*pair3(1)-1, 2*pair3(1) ]
  N = N(:,pairIndexes)
  Lambda = Lambda(pairIndexes,pairIndexes)

  !Fix sign to make diagonal entries positive
  IF( N(1,1) < 0 ) THEN
    N(:,1) = -1*N(:,1)
    N(:,2) = -1*N(:,2)
  ENDIF
  IF( N(3,3) < 0 ) THEN
    N(:,3) = -1*N(:,3)
    N(:,4) = -1*N(:,4)
  ENDIF
  IF( N(5,5) < 0 ) THEN
    N(:,5) = -1*N(:,5)
    N(:,6) = -1*N(:,6)
  ENDIF

  CONTAINS

    ELEMENTAL SUBROUTINE swap(a,b)
      REAL(rp), INTENT(INOUT):: a
      REAL(rp), INTENT(INOUT):: b
      REAL(rp) t

      t=b
      b=a
      a=t
    END SUBROUTINE swap

END SUBROUTINE real_and_symp

!+
! Subroutine project_emit_to_xyz(ring, ix, mode, sigma_x, sigma_y, sigma_z)
!
! Obtains the projected x,y, and z beamsizes by building the sigma matrix
! from the normal mode emittances and 1-turn transfer matrix.
! These projectes beamsize are what would be seen by instrumentation.
!
! This method of projecting takes into account transverse and longitudinal coupling.
!
! This method of obtaining the projected beam sizes is from "Alternitive approach to general
! coupled linear optics" by Andrzej Wolski.
!
! The normal mode emittances used to generate a beam envelop sigma matrix from the 
! 1-turn transfer matrix.  The projected sizes are from the 1,1 3,3 and 5,5 elements of
! the sigma matrix.
!
! Input:
!  ring             -- lat_struct: the storage ring
!  ix               -- integer: element at which to make the projection
!  mode             -- normal_modes_struct: normal mode emittances
!      %a%emittance -- real(rp): a-mode emittance
!      %b%emittance -- real(rp): b-mode emittance
!      %z%emittance -- real(rp): z-mode emittance
! Output:
!  sigma_x          -- real(rp): projected horizontal beamsize
!  sigma_y          -- real(rp): projected vertical beamsize
!  sigma_z          -- real(rp): projected longitudinal beamsize
!-
SUBROUTINE project_emit_to_xyz(ring, ix, mode, sigma_x, sigma_y, sigma_z)

  USE bmad
  USE eigen_mod

  IMPLICIT NONE

  TYPE(lat_struct) ring
  INTEGER ix
  TYPE(normal_modes_struct) mode
  REAL(rp) sigma_x, sigma_y, sigma_z
  REAL(rp) t6(6,6)

  REAL(rp) sigma_mat(6,6)
  LOGICAL error

  CALL transfer_matrix_calc (ring, .true., t6, ix1=ix, one_turn=.true.)
  CALL make_smat_from_abc(t6, mode, sigma_mat, error)

  sigma_x = SQRT(sigma_mat(1,1))
  sigma_y = SQRT(sigma_mat(3,3))
  sigma_z = SQRT(sigma_mat(5,5))
END SUBROUTINE project_emit_to_xyz

!- SUBROUTINE spatial_smat_from_canonical_smat_b(Ecan,Espatial)
!-   REAL(rp) Ecan(6,6)
!-   REAL(rp) Espatial(6,6)
!- 
!-   Espatial = Ecan
!-   Espatial(1,1) = Ecan(1,1) + Ecan(2,2)*Ecan(5,5) + 2.0d0*Ecan(2,5)**2
!-   Espatial(3,3) = Ecan(3,3) + Ecan(4,4)*Ecan(5,5) + 2.0d0*Ecan(4,5)**2
!-   Espatial(1,3) = Ecan(1,3) + Ecan(2,4)*Ecan(5,5) + 2.0d0*Ecan(2,5)*Ecan(4,5)
!-   Espatial(3,1) = Espatial(1,3)
!- END SUBROUTINE spatial_smat_from_canonical_smat_b

!----------------------------------------------
! Subroutines below are from original mode3_mod
!----------------------------------------------

!+
! Subroutine twiss3_propagate_all (lat)
!
! Subroutine to propagate the twiss parameters using all three normal modes.
!-

SUBROUTINE twiss3_propagate_all (lat)

IMPLICIT NONE

TYPE (lat_struct) lat

INTEGER i

DO i = 1, lat%n_ele_track
  call twiss3_propagate1 (lat%ele(i-1), lat%ele(i))
ENDDO

END SUBROUTINE twiss3_propagate_all

!+
! Subroutine twiss3_propagate1 (ele1, ele2)
!
! Subroutine to propagate the twiss parameters using all three normal modes.
!-

SUBROUTINE twiss3_propagate1 (ele1, ele2)

IMPLICIT NONE

TYPE mat2_struct
  REAL(rp) m(2,2)
END TYPE

TYPE (ele_struct) ele1, ele2
TYPE (mat2_struct) w(3)

REAL(rp) gamma(3), tv(6,6), w_inv(2,2)

INTEGER i, ik
LOGICAL err

!

IF (.NOT. ASSOCIATED(ele2%mode3)) ALLOCATE(ele2%mode3)

tv = MATMUL (ele2%mat6, ele1%mode3%v)

DO i = 1, 3
  ik = 2 * i - 1
  w(i)%m = tv(ik:ik+1,ik:ik+1)
  gamma(i) = SQRT(determinant (w(i)%m))
  w(i)%m = w(i)%m / gamma(i)
  call mat_symp_conj (w(i)%m, w_inv)
  ele2%mode3%v(1:6, ik:ik+1) = matmul(tv(1:6, ik:ik+1), w_inv)
ENDDO

ele2%mode3%x%eta = ele2%mode3%v(1,6)
ele2%mode3%y%eta = ele2%mode3%v(3,6)

ele2%mode3%x%etap = ele2%mode3%v(1,5)
ele2%mode3%y%etap = ele2%mode3%v(3,5)

call twiss1_propagate (ele1%mode3%a, w(1)%m,  ele2%value(l$), ele2%mode3%a, err)
call twiss1_propagate (ele1%mode3%b, w(2)%m,  ele2%value(l$), ele2%mode3%b, err)
call twiss1_propagate (ele1%mode3%c, w(3)%m,  0.0_rp,         ele2%mode3%c, err)

END SUBROUTINE

!+
! Subroutine twiss3_at_start (lat, error)
!
! Subroutine to calculate the twiss parameters of the three modes of the full 6D transfer
! matrix.
! Note: The rf must be on for this calculation.
!
! Modules needed:
!   use mode3_mod
!
! Input:
!   lat -- lat_struct: Lattice with
!
! Output:
!   lat   -- lat-struct:
!     %ele(0)  -- Ele_struct: Starting element
!       %mode3    -- Mode3_struct: Structure holding the normal modes.
!         %v(6,6)    -- Real(rp): V coupling matrix.
!         %a            -- Twiss_struct: "a" normal mode Twiss parameters.
!         %b            -- Twiss_struct: "b" normal mode Twiss parameters.
!         %c            -- Twiss_struct: "c" normal mode Twiss parameters.
!   error -- Logical: Set True if there is no RF. False otherwise.
!-

SUBROUTINE twiss3_at_start (lat, error)

IMPLICIT NONE

TYPE (lat_struct) lat
REAL(rp) g(6,6), tune3(3)
INTEGER n
LOGICAL error
CHARACTER(20) :: r_name = 'twiss3_at_start'

!

error = .true.

IF (.NOT. ASSOCIATED(lat%ele(0)%mode3)) ALLOCATE(lat%ele(0)%mode3)

CALL transfer_matrix_calc (lat, .true., lat%param%t1_with_RF, one_turn=.true.)
if (ALL(lat%param%t1_with_RF(6,1:5) == 0)) then
  call out_io (s_error$, r_name, 'RF IS OFF FOR THE MODE3 CALCULATION!')
  RETURN
ENDIF
CALL normal_mode3_calc (lat%param%t1_with_RF, tune3, g, lat%ele(0)%mode3%v)

lat%ele(0)%mode3%x%eta = lat%ele(0)%mode3%v(1,6)
lat%ele(0)%mode3%y%eta = lat%ele(0)%mode3%v(3,6)

lat%ele(0)%mode3%x%etap = lat%ele(0)%mode3%v(1,5)
lat%ele(0)%mode3%y%etap = lat%ele(0)%mode3%v(3,5)

CALL mode1_calc (g(1:2, 1:2), tune3(1), lat%ele(0)%mode3%a)
CALL mode1_calc (g(3:4, 3:4), tune3(2), lat%ele(0)%mode3%b)
CALL mode1_calc (g(5:6, 5:6), tune3(3), lat%ele(0)%mode3%c)

error = .false.

!-------------------------------------------------------------------------------------
CONTAINS

  SUBROUTINE mode1_calc (gg, tune, twiss)

  TYPE (twiss_struct) twiss
  REAL(rp) gg(:,:), tune

  !

  twiss%beta = gg(2,2)**2
  twiss%alpha = gg(2,1) * gg(2,2)
  twiss%gamma = (1 + twiss%alpha**2) / twiss%beta
  twiss%phi = 0

  END SUBROUTINE

END SUBROUTINE

END MODULE mode3_mod
